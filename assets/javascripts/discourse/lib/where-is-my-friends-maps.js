// Map utilities for where-is-my-friends plugin
import { ajax } from "discourse/lib/ajax";

export class MapManager {
  constructor(settings) {
    this.settings = settings;
    this.map = null;
    this.marker = null;
    this.provider = settings.map_provider || 'openstreetmap';
    this.fallbackToOSM = false;
  }

  // 初始化地图
  async initMap(container, options = {}) {
    const { lat = 39.9042, lng = 116.4074, zoom = 10 } = options;
    
    // 如果之前已经确定需要回退到OSM，直接使用OSM
    if (this.fallbackToOSM || this.provider === 'openstreetmap') {
      return await this.initOpenStreetMap(container, lat, lng, zoom);
    }
    
    try {
      switch (this.provider) {
        case 'amap':
          return await this.initAmapMap(container, lat, lng, zoom);
        case 'baidu':
          return await this.initBaiduMap(container, lat, lng, zoom);
        default:
          return await this.initOpenStreetMap(container, lat, lng, zoom);
      }
    } catch (error) {
      console.warn('地图初始化失败，回退到OpenStreetMap:', error);
      this.fallbackToOSM = true;
      this.provider = 'openstreetmap';
      return await this.initOpenStreetMap(container, lat, lng, zoom);
    }
  }

  // 高德地图初始化
  async initAmapMap(container, lat, lng, zoom) {
    try {
      if (!window.AMap) {
        await this.loadAmapScript();
      }

      this.map = new AMap.Map(container, {
        center: [lng, lat],
        zoom: zoom,
        resizeEnable: true
      });

      this.marker = new AMap.Marker({
        position: [lng, lat],
        draggable: true
      });
      
      this.map.add(this.marker);

      // 添加点击事件
      this.map.on('click', (e) => {
        const { lng, lat } = e.lnglat;
        this.updateMarker(lat, lng);
        this.onLocationSelect && this.onLocationSelect(lat, lng);
      });

      // 添加拖拽事件
      this.marker.on('dragend', (e) => {
        const { lng, lat } = e.lnglat;
        this.onLocationSelect && this.onLocationSelect(lat, lng);
      });

      return this.map;
    } catch (error) {
      console.warn('高德地图初始化失败:', error);
      throw error;
    }
  }

  // 百度地图初始化
  async initBaiduMap(container, lat, lng, zoom) {
    if (!window.BMap) {
      await this.loadBaiduScript();
    }

    this.map = new BMap.Map(container);
    const point = new BMap.Point(lng, lat);
    this.map.centerAndZoom(point, zoom);
    this.map.enableScrollWheelZoom(true);

    this.marker = new BMap.Marker(point, { enableDragging: true });
    this.map.addOverlay(this.marker);

    // 添加点击事件
    this.map.addEventListener('click', (e) => {
      const { lng, lat } = e.point;
      this.updateMarker(lat, lng);
      this.onLocationSelect && this.onLocationSelect(lat, lng);
    });

    // 添加拖拽事件
    this.marker.addEventListener('dragend', (e) => {
      const { lng, lat } = e.point;
      this.onLocationSelect && this.onLocationSelect(lat, lng);
    });

    return this.map;
  }

  // OpenStreetMap 初始化
  async initOpenStreetMap(container, lat, lng, zoom) {
    if (!window.L) {
      await this.loadLeafletScript();
    }

    this.map = L.map(container).setView([lat, lng], zoom);
    
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors'
    }).addTo(this.map);

    this.marker = L.marker([lat, lng], { draggable: true }).addTo(this.map);

    // 添加点击事件
    this.map.on('click', (e) => {
      const { lat, lng } = e.latlng;
      this.updateMarker(lat, lng);
      this.onLocationSelect && this.onLocationSelect(lat, lng);
    });

    // 添加拖拽事件
    this.marker.on('dragend', (e) => {
      const { lat, lng } = e.target.getLatLng();
      this.onLocationSelect && this.onLocationSelect(lat, lng);
    });

    return this.map;
  }

  // 更新标记位置
  updateMarker(lat, lng) {
    if (!this.marker) {
      console.warn('MapManager: Marker is not initialized, cannot update position');
      return;
    }
    
    switch (this.provider) {
      case 'amap':
        if (this.marker && this.marker.setPosition) {
          this.marker.setPosition([lng, lat]);
        }
        break;
      case 'baidu':
        if (this.marker && this.marker.setPosition) {
          this.marker.setPosition(new BMap.Point(lng, lat));
        }
        break;
      default: // OpenStreetMap
        if (this.marker && this.marker.setLatLng) {
          this.marker.setLatLng([lat, lng]);
        }
        break;
    }
  }

  // 设置位置选择回调
  onLocationSelect(callback) {
    this.onLocationSelect = callback;
  }

  // 销毁地图
  destroy() {
    if (this.map) {
      switch (this.provider) {
        case 'amap':
          this.map.destroy();
          break;
        case 'baidu':
          // 百度地图没有destroy方法，清空即可
          break;
        default:
          this.map.remove();
          break;
      }
      this.map = null;
      this.marker = null;
    }
  }

  // 动态加载高德地图脚本
  async loadAmapScript() {
    return new Promise((resolve, reject) => {
      if (window.AMap) {
        resolve();
        return;
      }

      const script = document.createElement('script');
      script.src = `https://webapi.amap.com/maps?v=1.4.15&key=${this.settings.amap_api_key}`;
      
      // 设置超时
      const timeout = setTimeout(() => {
        reject(new Error('Amap script loading timeout'));
      }, 10000);
      
      script.onload = () => {
        clearTimeout(timeout);
        // 检查是否真的加载成功
        if (window.AMap) {
          resolve();
        } else {
          reject(new Error('Amap loaded but AMap object not available'));
        }
      };
      
      script.onerror = (error) => {
        clearTimeout(timeout);
        reject(new Error('Failed to load Amap script: ' + error.message));
      };
      
      try {
        document.head.appendChild(script);
      } catch (error) {
        clearTimeout(timeout);
        reject(new Error('Failed to append Amap script: CSP restriction'));
      }
    });
  }

  // 动态加载百度地图脚本
  async loadBaiduScript() {
    return new Promise((resolve, reject) => {
      if (window.BMap) {
        resolve();
        return;
      }

      const script = document.createElement('script');
      script.src = `https://api.map.baidu.com/api?v=3.0&ak=${this.settings.baidu_api_key}`;
      script.onload = resolve;
      script.onerror = () => reject(new Error('Failed to load Baidu map script'));
      document.head.appendChild(script);
    });
  }

  // 动态加载Leaflet脚本和CSS
  async loadLeafletScript() {
    return new Promise((resolve, reject) => {
      if (window.L) {
        resolve();
        return;
      }

      // Load CSS first
      const css = document.createElement('link');
      css.rel = 'stylesheet';
      css.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
      document.head.appendChild(css);

      // Then load JS
      const script = document.createElement('script');
      script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
      script.onload = resolve;
      script.onerror = () => reject(new Error('Failed to load Leaflet script'));
      document.head.appendChild(script);
    });
  }
}

// 地址解析工具
export class GeocodingHelper {
  static async getAddressFromCoords(lat, lng, provider = 'amap') {
    try {
      switch (provider) {
        case 'amap':
          return await this.getAmapAddress(lat, lng);
        case 'baidu':
          return await this.getBaiduAddress(lat, lng);
        default:
          return await this.getOSMAddress(lat, lng);
      }
    } catch (error) {
      console.warn('Failed to get address:', error);
      return `纬度: ${lat.toFixed(6)}, 经度: ${lng.toFixed(6)}`;
    }
  }

  static async getAmapAddress(lat, lng) {
    // 这里可以通过后端代理调用高德地图逆地理编码API
    // 为了安全起见，不在前端直接调用
    return `纬度: ${lat.toFixed(6)}, 经度: ${lng.toFixed(6)}`;
  }

  static async getBaiduAddress(lat, lng) {
    // 这里可以通过后端代理调用百度地图逆地理编码API
    return `纬度: ${lat.toFixed(6)}, 经度: ${lng.toFixed(6)}`;
  }

  static async getOSMAddress(lat, lng) {
    try {
      const response = await fetch(
        `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&accept-language=zh-CN`
      );
      const data = await response.json();
      return data.display_name || `纬度: ${lat.toFixed(6)}, 经度: ${lng.toFixed(6)}`;
    } catch (error) {
      return `纬度: ${lat.toFixed(6)}, 经度: ${lng.toFixed(6)}`;
    }
  }
} 