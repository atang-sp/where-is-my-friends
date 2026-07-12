import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

export default {
  name: "where-is-my-friends",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.where_is_my_friends_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.addCommunitySectionLink({
        name: "where-is-my-friends",
        route: "where-is-my-friends",
        title: i18n("where_is_my_friends.title"),
        text: i18n("where_is_my_friends.title"),
        icon: "location-dot",
      });

      api.addSaveableUserOption("where_is_my_friends_notify_city", {
        page: "notifications",
      });
    });
  },
};
