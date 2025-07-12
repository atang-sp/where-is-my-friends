// where-is-my-friends Geolocation helper based on MDN docs

/*
 * Returns a Promise that resolves with { coords: { latitude, longitude, accuracy, ... }, timestamp }
 * or rejects with a structured error { code, message } like the original GeolocationPositionError.
 * Default options:
 *   - enableHighAccuracy: true   (better precision if available)
 *   - timeout: 10000             (10 s max wait)
 *   - maximumAge: 0              (do not use cached positions)
 */
export function getCurrentPositionAsync(options = {}) {
  const defaultOpts = {
    enableHighAccuracy: true,
    timeout: 10000,
    maximumAge: 0
  };

  const opts = Object.assign({}, defaultOpts, options);

  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      return reject({ code: 0, message: "Geolocation API not supported in this browser." });
    }

    navigator.geolocation.getCurrentPosition(
      position => resolve(position),
      error => reject(error),
      opts
    );
  });
}

/*
 * (Optional) Watch position helper – returns { clear() } to stop.
 * Not used for now but provided for extensibility.
 */
export function watchPosition(handler, errorHandler, options = {}) {
  if (!navigator.geolocation) {
    throw new Error("Geolocation API not supported in this browser.");
  }
  const id = navigator.geolocation.watchPosition(handler, errorHandler, options);
  return {
    clear() {
      navigator.geolocation.clearWatch(id);
    }
  };
} 