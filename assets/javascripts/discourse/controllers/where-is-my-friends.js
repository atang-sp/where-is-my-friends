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
      this.set("error", "Failed to get location: " + error.message);
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
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 60000
      });
    });
  }
} 