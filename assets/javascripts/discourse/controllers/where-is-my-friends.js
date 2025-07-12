import Controller from "@ember/controller";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";

export default class WhereIsMyFriendsController extends Controller {
  @action
  async shareLocation() {
    if (!navigator.geolocation) {
      this.set("error", "Geolocation is not supported by this browser.");
      return;
    }

    // Set loading state
    this.set("loading", true);
    this.set("error", null);

    try {
      const position = await this.getCurrentPosition();
      const { latitude, longitude } = position.coords;
      
      await ajax("/api/where-is-my-friends/locations", {
        type: "POST",
        data: { latitude, longitude }
      });
      
      this.set("locationShared", true);
      this.set("error", null);
      
      // Refresh the model to get updated data
      this.send("refreshModel");
    } catch (error) {
      let errorMessage = "Failed to get location: ";
      
      // Handle specific geolocation errors
      switch (error.code) {
        case error.PERMISSION_DENIED:
          errorMessage = "Location access denied. Please allow location access in your browser settings and try again.";
          break;
        case error.POSITION_UNAVAILABLE:
          errorMessage = "Location information is unavailable. Please check your device's location services.";
          break;
        case error.TIMEOUT:
          errorMessage = "Location request timed out. Please try again or check your internet connection.";
          break;
        default:
          errorMessage += error.message;
      }
      
      this.set("error", errorMessage);
    } finally {
      this.set("loading", false);
    }
  }

  @action
  async findNearbyUsers() {
    if (!this.currentUser?.location) {
      this.set("error", "Please share your location first.");
      return;
    }

    try {
      const { latitude, longitude } = this.currentUser.location;
      const result = await ajax("/api/where-is-my-friends/locations/nearby", {
        data: { latitude, longitude, distance: 10 }
      });
      
      this.set("nearbyUsers", result.users);
      this.set("error", null);
    } catch (error) {
      this.set("error", "Failed to find nearby users: " + error.message);
    }
  }

  @action
  async removeLocation() {
    try {
      await ajax("/api/where-is-my-friends/locations", {
        type: "DELETE"
      });
      
      this.set("locationShared", false);
      this.set("error", null);
      
      // Refresh the model
      this.send("refreshModel");
    } catch (error) {
      this.set("error", "Failed to remove location: " + error.message);
    }
  }

  getCurrentPosition() {
    return new Promise((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(resolve, reject, {
        enableHighAccuracy: false, // Use false for faster response
        timeout: 30000, // Increase timeout to 30 seconds
        maximumAge: 300000 // Cache for 5 minutes
      });
    });
  }
} 