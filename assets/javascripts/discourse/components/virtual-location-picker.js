import Component from "@ember/component";
import { MapManager, GeocodingHelper } from "discourse/plugins/where-is-my-friends/discourse/lib/where-is-my-friends-maps";

export default Component.extend({
  tagName: 'div',
  classNames: ['virtual-location-picker'],

  // 组件状态
  selectedLat: null,
  selectedLng: null,
  selectedAddress: '',
  mapManager: null,
  isMapReady: false,
  mapError: null,

  // 默认位置（北京）
  defaultLat: 39.9042,
  defaultLng: 116.4074,

  didInsertElement() {
    this._super(...arguments);
    this.initializeMap();
  },

  willDestroyElement() {
    this._super(...arguments);
    if (this.get('mapManager')) {
      this.get('mapManager').destroy();
    }
  },

  async initializeMap() {
    try {
      this.set('mapError', null);
      this.set('isMapReady', false);

      const container = document.getElementById('virtual-map-container');
      if (!container) {
        throw new Error('地图容器未找到');
      }

      // 获取默认位置（北京）
      const defaultLat = 39.9042;
      const defaultLng = 116.4074;

      const mapManager = new MapManager({
        map_provider: this.get('settings.map_provider') || 'openstreetmap',
        amap_api_key: this.get('settings.amap_api_key'),
        baidu_api_key: this.get('settings.baidu_api_key')
      });

      this.set('mapManager', mapManager);

      // 设置位置选择回调
      mapManager.onLocationSelect = (lat, lng) => {
        this.onLocationSelected(lat, lng);
      };

      // 初始化地图
      await mapManager.initMap(container, {
        lat: defaultLat,
        lng: defaultLng,
        zoom: 10
      });

      this.set('isMapReady', true);
      
      // 确保标记已创建
      if (!mapManager.marker) {
        console.warn('Virtual location picker: Marker not created during map initialization');
      }

    } catch (error) {
      console.error('Virtual location picker map initialization failed:', error);
      this.set('mapError', '地图加载失败: ' + error.message);
      this.set('isMapReady', false);
    }
  },

  async onLocationSelected(lat, lng) {
    try {
      this.set('selectedLat', lat);
      this.set('selectedLng', lng);
      
      // 获取地址信息
      await this.updateSelectedAddress();
    } catch (error) {
      console.error('Location selection error:', error);
    }
  },

  async updateSelectedAddress() {
    const lat = this.get('selectedLat');
    const lng = this.get('selectedLng');
    const mapManager = this.get('mapManager');
    
    if (!lat || !lng || !mapManager) {
      return;
    }

    try {
      const provider = mapManager.provider;
      const address = await GeocodingHelper.getAddressFromCoords(lat, lng, provider);
      this.set('selectedAddress', address);
    } catch (error) {
      console.warn('Failed to get address:', error);
      this.set('selectedAddress', `${lat.toFixed(6)}, ${lng.toFixed(6)}`);
    }
  },

  actions: {
    confirmLocation() {
      const selectedLat = this.get('selectedLat');
      const selectedLng = this.get('selectedLng');
      const selectedAddress = this.get('selectedAddress');
      
      if (selectedLat && selectedLng) {
        if (this.get('onConfirm')) {
          this.get('onConfirm')({
            latitude: selectedLat,
            longitude: selectedLng,
            address: selectedAddress
          });
        }
      }
    },

    cancelSelection() {
      if (this.get('onCancel')) {
        this.get('onCancel')();
      }
    },

    getCurrentLocation() {
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(
          (position) => {
            const { latitude, longitude } = position.coords;
            const mapManager = this.get('mapManager');
            if (mapManager && mapManager.marker) {
              // 更新标记位置
              mapManager.updateMarker(latitude, longitude);
              
              // 更新地图中心
              if (mapManager.map) {
                switch (mapManager.provider) {
                  case 'amap':
                    mapManager.map.setCenter([longitude, latitude]);
                    break;
                  case 'baidu':
                    mapManager.map.panTo(new BMap.Point(longitude, latitude));
                    break;
                  default: // OpenStreetMap
                    mapManager.map.setView([latitude, longitude], mapManager.map.getZoom());
                    break;
                }
              }
              
              // 触发位置选择事件
              this.onLocationSelected(latitude, longitude);
            }
          },
          (error) => {
            console.error('Geolocation error:', error);
            this.set('mapError', '获取当前位置失败: ' + error.message);
          },
          {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 60000
          }
        );
      } else {
        this.set('mapError', '此浏览器不支持地理位置功能');
      }
    }
  }
}); 