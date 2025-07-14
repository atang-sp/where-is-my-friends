import Controller from "@ember/controller";
import { ajax } from "discourse/lib/ajax";
import { getCurrentPositionAsync } from "discourse/plugins/where-is-my-friends/discourse/lib/where-is-my-friends-geolocation";

export default Controller.extend({
  // 虚拟定位相关状态
  showVirtualLocationPicker: false,
  virtualLocationData: null,
  locationMode: 'real', // 'real' or 'virtual'
  
  actions: {
    async shareLocation() {
      // 检查是否启用虚拟定位功能
      if (this.siteSettings.where_is_my_friends_enable_virtual_location) {
        // 显示位置选择器
        this.send('showLocationModeSelector');
        return;
      }
      
      // 使用原有的真实定位逻辑
      await this.send('shareRealLocation');
    },
    
    showLocationModeSelector() {
      // 显示位置模式选择对话框
      this.set("showLocationModeDialog", true);
    },
    
    selectRealLocation() {
      this.set("showLocationModeDialog", false);
      this.set("locationMode", 'real');
      this.send('shareRealLocation');
    },
    
    selectVirtualLocation() {
      this.set("showLocationModeDialog", false);
      this.set("locationMode", 'virtual');
      this.set("showVirtualLocationPicker", true);
    },
    
    async shareRealLocation() {
      // 首先检查基本环境
      const environmentCheck = this.checkEnvironment();
      if (!environmentCheck.supported) {
        this.set("error", environmentCheck.message);
        return;
      }

      // Set loading state
      this.set("loading", true);
      this.set("error", null);
      this.set("debugInfo", null);

      let latitude, longitude;

      // 1) 尝试浏览器原生定位
      try {
        const position = await getCurrentPositionAsync({ enableHighAccuracy: false, timeout: 8000, maximumAge: 600000 });
        ({ latitude, longitude } = position.coords);
      } catch (geoError) {
        console.warn("HTML5 geolocation failed, fallback to IP geolocation", geoError);
        // 2) 尝试 ip-api.com 定位
        try {
          const loc = await this.getLocationViaIp();
          ({ latitude, longitude } = loc);
        } catch (fallbackError) {
          const errorMsg = fallbackError.message || fallbackError;
          this.set("error", `IP 定位失败: ${errorMsg}`);
          this.set("debugInfo", { error: errorMsg });
          this.set("loading", false);
          return;
        }
      }

      try {
        // 保存真实位置信息
        await ajax("/api/where-is-my-friends/locations", {
          type: "POST",
          data: { 
            latitude, 
            longitude,
            is_virtual: false
          }
        });

        this.set("locationShared", true);
        this.set("error", null);
        this.set("locationStatus", null);

        // 更新当前用户的位置信息
        this.set("currentUser.location", { 
          latitude, 
          longitude,
          is_virtual: false,
          location_type: 'real'
        });

        console.log('✅ 真实位置信息已保存');

        // 清除附近用户列表（因为位置已更新）
        this.set("nearbyUsers", null);

        // 刷新模型数据
        this.send("refreshModel");

      } catch (error) {
        const errorInfo = this.handleGeolocationError(error);
        this.set("error", errorInfo.message);
        this.set("debugInfo", errorInfo.debug);
      } finally {
        this.set("loading", false);
      }
    },

    onVirtualLocationConfirm(locationData) {
      this.set("virtualLocationData", locationData);
      this.shareVirtualLocation(locationData.latitude, locationData.longitude, locationData.address);
    },

    onVirtualLocationCancel() {
      this.set("showVirtualLocationPicker", false);
      this.set("virtualLocationData", null);
    },

    async findNearbyUsers() {
      // 首先检查用户是否已经分享了位置
      if (!this.currentUser?.location) {
        this.set("error", "请先分享您的位置信息。");
        return;
      }

      this.set("loading", true);
      this.set("error", null);

      try {
        const { latitude, longitude } = this.currentUser.location;
        console.log('🔍 查找附近用户，位置:', { latitude, longitude });
        
        const distance = this.siteSettings.where_is_my_friends_default_distance_km;
        const result = await ajax("/api/where-is-my-friends/locations/nearby", {
          data: { latitude, longitude, distance }
        });
        
        console.log('✅ 找到附近用户:', result.users?.length || 0, '个');
        this.set("nearbyUsers", result.users || []);
        this.set("error", null);
      } catch (error) {
        console.error('❌ 查找附近用户失败:', error);
        let errMsg = error?.errors?.[0] || error?.message || (error.jqXHR && error.jqXHR.responseJSON?.errors?.[0]);
        if (!errMsg && typeof error === "string") {
          errMsg = error;
        }
        this.set("error", `查找附近用户失败: ${errMsg || '未知错误'}`);
      } finally {
        this.set("loading", false);
      }
    },

    async removeLocation() {
      try {
        await ajax("/api/where-is-my-friends/locations", {
          type: "DELETE"
        });
        
        this.set("locationShared", false);
        this.set("error", null);
        this.set("nearbyUsers", null); // 清除附近用户列表
        this.set("showVirtualLocationPicker", false);
        this.set("virtualLocationData", null);
        
        // 刷新当前用户的位置信息
        this.set("currentUser.location", null);
        
        console.log('✅ 位置信息已移除');
        
        // 刷新模型数据
        this.send("refreshModel");
      } catch (error) {
        console.error('❌ 移除位置失败:', error);
        this.set("error", "移除位置失败: " + (error.message || error));
      }
    },

    async checkPermissions() {
      try {
        if (navigator.permissions && navigator.permissions.query) {
          const permission = await navigator.permissions.query({ name: 'geolocation' });
          this.set("permissionStatus", permission.state);
          return permission.state;
        }
      } catch (error) {
        console.log("无法检查权限状态:", error);
      }
      return "unknown";
    }
  },

  async shareVirtualLocation(latitude, longitude, address) {
    this.set("loading", true);
    this.set("error", null);
    this.set("showVirtualLocationPicker", false);

    // 验证参数
    if (!latitude || !longitude) {
      this.set("error", "无效的位置坐标");
      this.set("loading", false);
      return;
    }

    // 确保地址不为空
    const virtualAddress = address || `纬度: ${latitude.toFixed(6)}, 经度: ${longitude.toFixed(6)}`;

    try {
      console.log('🔄 正在保存虚拟位置...', { latitude, longitude, address: virtualAddress });

      // 保存虚拟位置信息
      const response = await ajax("/api/where-is-my-friends/locations", {
        type: "POST",
        data: { 
          latitude: latitude, 
          longitude: longitude,
          is_virtual: true,
          virtual_address: virtualAddress
        }
      });

      this.set("locationShared", true);
      this.set("error", null);

      // 更新当前用户的位置信息
      this.set("currentUser.location", { 
        latitude, 
        longitude,
        is_virtual: true,
        virtual_address: virtualAddress,
        location_type: 'virtual'
      });

      console.log('✅ 虚拟位置信息已保存', response);

      // 清除附近用户列表（因为位置已更新）
      this.set("nearbyUsers", null);

      // 刷新模型数据
      this.send("refreshModel");

    } catch (error) {
      console.error('❌ 保存虚拟位置失败:', error);
      
      let errorMessage = "保存虚拟位置失败";
      if (error.jqXHR && error.jqXHR.responseJSON && error.jqXHR.responseJSON.errors) {
        errorMessage = error.jqXHR.responseJSON.errors.join(', ');
      } else if (error.message) {
        errorMessage = error.message;
      }
      
      this.set("error", errorMessage);
    } finally {
      this.set("loading", false);
    }
  },

  checkEnvironment() {
    // 检查浏览器支持
    if (!navigator.geolocation) {
      return {
        supported: false,
        message: "此浏览器不支持地理位置功能。请使用Chrome、Firefox、Safari或Edge浏览器。"
      };
    }

    // 检查HTTPS（Chrome要求）
    if (location.protocol !== 'https:' && location.hostname !== 'localhost') {
      return {
        supported: false,
        message: "地理位置功能需要HTTPS连接。请使用HTTPS访问此网站。"
      };
    }

    // 检查是否在Chrome中
    const isChrome = /Chrome/.test(navigator.userAgent) && /Google Inc/.test(navigator.vendor);
    
    return {
      supported: true,
      isChrome: isChrome,
      message: null
    };
  },

  handleGeolocationError(error) {
    let message = "";
    let debug = {
      errorCode: error.code,
      errorMessage: error.message,
      userAgent: navigator.userAgent,
      protocol: location.protocol,
      hostname: location.hostname
    };

    switch (error.code) {
      case error.PERMISSION_DENIED:
        message = this.getPermissionDeniedMessage();
        debug.errorType = "PERMISSION_DENIED";
        break;
      case error.POSITION_UNAVAILABLE:
        message = this.getPositionUnavailableMessage();
        debug.errorType = "POSITION_UNAVAILABLE";
        break;
      case error.TIMEOUT:
        message = this.getTimeoutMessage();
        debug.errorType = "TIMEOUT";
        break;
      default:
        message = `获取位置时发生未知错误: ${error.message}`;
        debug.errorType = "UNKNOWN";
    }

    return { message, debug };
  },

  getPermissionDeniedMessage() {
    const isChrome = /Chrome/.test(navigator.userAgent);
    
    if (isChrome) {
      return `
        <strong>位置访问被拒绝</strong><br><br>
        <strong>Chrome浏览器解决方案：</strong><br>
        1. 点击地址栏左侧的锁定图标 🔒<br>
        2. 将"位置"设置为"允许"<br>
        3. 刷新页面后重试<br><br>
        <strong>如果问题持续：</strong><br>
        1. 打开Chrome设置 → 隐私设置和安全性 → 网站设置 → 位置信息<br>
        2. 确保此网站没有被阻止<br>
        3. 清除浏览器缓存和Cookie<br>
        4. 重启Chrome浏览器
      `;
    } else {
      return `
        <strong>位置访问被拒绝</strong><br><br>
        请在浏览器设置中允许位置访问，然后重试。
      `;
    }
  },

  getPositionUnavailableMessage() {
    return `
      <strong>位置信息不可用</strong><br><br>
      <strong>可能的原因：</strong><br>
      1. 设备的位置服务被禁用<br>
      2. GPS信号弱或无信号<br>
      3. 网络连接问题<br><br>
      <strong>解决方案：</strong><br>
      1. 检查设备的位置服务设置<br>
      2. 确保GPS已开启<br>
      3. 尝试在室外或靠近窗户的地方使用<br>
      4. 检查网络连接
    `;
  },

  getTimeoutMessage() {
    return `
      <strong>位置请求超时</strong><br><br>
      <strong>可能的原因：</strong><br>
      1. 网络连接慢<br>
      2. GPS信号弱<br>
      3. 位置服务响应慢<br>
      4. 设备位置服务设置问题<br><br>
      <strong>立即解决方案：</strong><br>
      1. <strong>检查网络连接</strong> - 确保网络稳定<br>
      2. <strong>尝试在室外使用</strong> - GPS信号在室内较弱<br>
      3. <strong>等待几秒钟后重试</strong> - 位置服务可能需要时间<br>
      4. <strong>重启设备的位置服务</strong><br><br>
      <strong>Chrome特定解决方案：</strong><br>
      1. 打开Chrome设置 → 隐私设置和安全性 → 网站设置 → 位置信息<br>
      2. 确保此网站设置为"允许"<br>
      3. 清除浏览器缓存（Ctrl+Shift+Delete）<br>
      4. 重启Chrome浏览器<br><br>
      <strong>如果问题持续：</strong><br>
      1. 尝试使用无痕模式（Ctrl+Shift+N）<br>
      2. 禁用Chrome扩展程序<br>
      3. 更新Chrome到最新版本<br>
      4. 尝试其他浏览器（Firefox、Safari、Edge）
    `;
  },

  // getCurrentPosition() 方法已抽离到 discourse/lib/where-is-my-friends-geolocation.js
  // 保留空实现以防其它代码引用
  getCurrentPosition() {
    return getCurrentPositionAsync();
  },

  async getLocationViaIp() {
    const data = await ajax("/api/where-is-my-friends/ip-location");
    const parsed = typeof data === "string" ? JSON.parse(data) : data;

    if (parsed && parsed.lat !== undefined && parsed.lon !== undefined) {
      return { latitude: parsed.lat, longitude: parsed.lon };
    }

    throw new Error(parsed.message || "IP 位置服务返回错误");
  }
}); 