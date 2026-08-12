import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";

export default class WhereIsMyFriendsTagsRoute extends DiscourseRoute {
  @service currentUser;
  @service router;
  @service siteSettings;

  redirect() {
    if (
      !this.currentUser ||
      !this.siteSettings.where_is_my_friends_enabled ||
      !this.siteSettings.where_is_my_friends_user_tags_enabled
    ) {
      this.router.replaceWith("discovery");
    }
  }
}
