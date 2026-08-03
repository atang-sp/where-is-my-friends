import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

export default class UserActivityDynamicsRoute extends DiscourseRoute {
  @service currentUser;
  @service router;
  @service siteSettings;

  model() {
    return this.modelFor("user");
  }

  redirect() {
    if (
      !this.currentUser ||
      !this.siteSettings.where_is_my_friends_enabled ||
      !this.siteSettings.where_is_my_friends_dynamics_enabled
    ) {
      this.router.replaceWith("userActivity");
    }
  }

  renderTemplate() {
    this.render("user-activity/dynamics");
  }
}
