import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class WhereIsMyFriendsRoute extends DiscourseRoute {
  model() {
    return ajax("/api/where-is-my-friends").catch(error => {
      console.error("Error loading where-is-my-friends data:", error);
      return {
        currentUser: null,
        users: []
      };
    });
  }

  setupController(controller, model) {
    controller.setProperties({
      currentUser: model.currentUser || null,
      users: model.users || []
    });
  }
}