import Controller from "@ember/controller";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default Controller.extend({
  nearbyUsers: [],
  loading: false,
  currentLocation: null,

  shareLocation: action(async function() {
    if (!navigator.geolocation) {
      this.showError("Geolocation is not supported by this browser.");
      return;
    }

    this.set("loading", true);

    try {
      const position = await this.getCurrentPosition();
      const { latitude, longitude } = position.coords;

      await ajax("/where-is-my-friends/locations", {
        type: "POST",
        data: { latitude, longitude }
      });

      this.set("currentLocation", { latitude, longitude });
      this.showSuccess("Location shared successfully!");
      this.searchNearbyUsers();
    } catch (error) {
      if (error.code === 1) {
        this.showError("Location access denied. Please allow location access to use this feature.");
      } else {
        popupAjaxError(error);
      }
    } finally {
      this.set("loading", false);
    }
  }),

  removeLocation: action(async function() {
    try {
      await ajax("/where-is-my-friends/locations", {
        type: "DELETE"
      });

      this.set("currentLocation", null);
      this.set("nearbyUsers", []);
      this.showSuccess("Location removed successfully!");
    } catch (error) {
      popupAjaxError(error);
    }
  }),

  searchNearbyUsers: action(async function() {
    if (!this.currentLocation) {
      this.showError("Please share your location first.");
      return;
    }

    this.set("loading", true);

    try {
      const distance = document.getElementById("distance")?.value || 5;
      const result = await ajax("/where-is-my-friends/locations/nearby", {
        data: {
          latitude: this.currentLocation.latitude,
          longitude: this.currentLocation.longitude,
          distance: distance
        }
      });

      this.set("nearbyUsers", result.users || []);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.set("loading", false);
    }
  }),

  getCurrentPosition() {
    return new Promise((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(resolve, reject, {
        enableHighAccuracy: false,
        timeout: 10000,
        maximumAge: 300000 // 5 minutes
      });
    });
  },

  showSuccess(message) {
    // You can implement a proper notification system here
    console.log("Success:", message);
  },

  showError(message) {
    console.error("Error:", message);
  }
}); 