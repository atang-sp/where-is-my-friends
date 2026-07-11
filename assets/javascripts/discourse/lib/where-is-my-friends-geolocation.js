export function getCurrentPositionAsync(options = {}) {
  const geolocation = globalThis.navigator?.geolocation;
  if (!geolocation) {
    return Promise.reject(new Error("geolocation_not_supported"));
  }

  return new Promise((resolve, reject) => {
    geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: true,
      timeout: 10_000,
      maximumAge: 0,
      ...options,
    });
  });
}
