import Component from "@glimmer/component";
import { service } from "@ember/service";
import PersonalDynamicsHomepageFeed from "discourse/plugins/where-is-my-friends/discourse/components/personal-dynamics-homepage-feed";

export default class PersonalDynamicsHomepageFeedConnector extends Component {
  static shouldRender(_args, { currentUser, siteSettings }) {
    return Boolean(
      currentUser &&
      siteSettings.where_is_my_friends_enabled &&
      !siteSettings.where_is_my_friends_first_connection_enabled &&
      siteSettings.where_is_my_friends_dynamics_enabled &&
      siteSettings.where_is_my_friends_dynamics_feed_enabled &&
      siteSettings.where_is_my_friends_dynamics_category_id
    );
  }

  @service router;

  get isHomeRoute() {
    const routeName = this.router.currentRouteName ?? "";
    return (
      !this.isCategoryRoute &&
      (routeName === "discovery" || routeName.startsWith("discovery."))
    );
  }

  get isCategoryRoute() {
    const routeName = this.router.currentRouteName ?? "";
    return Boolean(
      routeName === "discovery.categories" ||
      routeName.startsWith("category.") ||
      this.router.currentRoute?.attributes?.category
    );
  }

  <template>
    {{#if this.isHomeRoute}}
      <PersonalDynamicsHomepageFeed />
    {{/if}}
  </template>
}
