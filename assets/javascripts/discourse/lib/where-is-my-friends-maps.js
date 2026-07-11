import loadScript, { loadCSS } from "discourse/lib/load-script";

const PLUGIN_PATH = "/plugins/where-is-my-friends";
const DEFAULT_CENTER = { latitude: 31.2304, longitude: 121.4737 };

export function resolveMapProvider(settings = {}) {
  if (settings.map_provider === "amap" && settings.amap_api_key) {
    return "amap";
  }
  if (settings.map_provider === "baidu" && settings.baidu_api_key) {
    return "baidu";
  }
  return "openstreetmap";
}

export function providerLabel(provider) {
  return { amap: "高德地图", baidu: "百度地图", openstreetmap: "OpenStreetMap" }[
    provider
  ];
}

export class MapManager {
  constructor(settings = {}) {
    this.settings = settings;
    this.provider = resolveMapProvider(settings);
  }

  async init(container, options = {}) {
    const latitude = options.latitude ?? DEFAULT_CENTER.latitude;
    const longitude = options.longitude ?? DEFAULT_CENTER.longitude;

    if (this.provider === "amap") {
      return this.initAmap(container, latitude, longitude);
    }
    if (this.provider === "baidu") {
      return this.initBaidu(container, latitude, longitude);
    }
    return this.initOpenStreetMap(container, latitude, longitude);
  }

  setSelectionHandler(callback) {
    this.selectionHandler = callback;
  }

  async initOpenStreetMap(container, latitude, longitude) {
    await Promise.all([
      loadCSS(`${PLUGIN_PATH}/stylesheets/leaflet-1.9.4.css`),
      loadScript(`${PLUGIN_PATH}/javascripts/leaflet-1.9.4.js`),
    ]);

    const leaflet = window.L;
    if (!leaflet) {
      throw new Error("Leaflet did not initialize");
    }

    this.map = leaflet.map(container).setView([latitude, longitude], 11);
    leaflet
      .tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: "© OpenStreetMap contributors",
        maxZoom: 19,
      })
      .addTo(this.map);
    this.marker = leaflet
      .circleMarker([latitude, longitude], {
        radius: 9,
        weight: 3,
        color: "#fff",
        fillColor: "#e4572e",
        fillOpacity: 1,
      })
      .addTo(this.map);
    this.map.on("click", ({ latlng }) => this.select(latlng.lat, latlng.lng));
  }

  async initAmap(container, latitude, longitude) {
    await loadScript(
      `https://webapi.amap.com/maps?v=2.0&key=${encodeURIComponent(
        this.settings.amap_api_key
      )}`
    );
    const amap = window.AMap;
    if (!amap) {
      throw new Error("Amap did not initialize");
    }

    this.map = new amap.Map(container, { center: [longitude, latitude], zoom: 11 });
    this.marker = new amap.Marker({ position: [longitude, latitude] });
    this.map.add(this.marker);
    this.map.on("click", ({ lnglat }) => this.select(lnglat.lat, lnglat.lng));
  }

  async initBaidu(container, latitude, longitude) {
    await loadScript(
      `https://api.map.baidu.com/api?v=3.0&ak=${encodeURIComponent(
        this.settings.baidu_api_key
      )}`
    );
    const baidu = window.BMap;
    if (!baidu) {
      throw new Error("Baidu map did not initialize");
    }

    const point = new baidu.Point(longitude, latitude);
    this.map = new baidu.Map(container);
    this.map.centerAndZoom(point, 11);
    this.map.enableScrollWheelZoom(true);
    this.marker = new baidu.Marker(point);
    this.map.addOverlay(this.marker);
    this.map.addEventListener("click", ({ point: selected }) =>
      this.select(selected.lat, selected.lng)
    );
  }

  select(latitude, longitude) {
    this.updateMarker(latitude, longitude);
    this.selectionHandler?.({ latitude, longitude });
  }

  updateMarker(latitude, longitude) {
    if (!this.marker) {
      return;
    }

    if (this.provider === "amap") {
      this.marker.setPosition([longitude, latitude]);
    } else if (this.provider === "baidu") {
      this.marker.setPosition(new window.BMap.Point(longitude, latitude));
    } else {
      this.marker.setLatLng([latitude, longitude]);
    }
  }

  destroy() {
    if (this.provider === "amap") {
      this.map?.destroy();
    } else if (this.provider === "openstreetmap") {
      this.map?.remove();
    }
    this.map = null;
    this.marker = null;
    this.selectionHandler = null;
  }
}
