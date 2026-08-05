import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

export default class WhereIsMyFriendsDynamicsRoute extends DiscourseRoute {
  @service currentUser;
  @service router;
  @service siteSettings;

  redirect() {
    if (
      !this.currentUser ||
      !this.siteSettings.where_is_my_friends_enabled ||
      !this.siteSettings.where_is_my_friends_dynamics_enabled ||
      !this.siteSettings.where_is_my_friends_dynamics_feed_enabled ||
      !this.siteSettings.where_is_my_friends_dynamics_category_id
    ) {
      this.router.replaceWith("discovery");
    }
  }
}
