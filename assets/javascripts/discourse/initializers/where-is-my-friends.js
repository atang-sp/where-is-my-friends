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
      api.addNavigationBarItem({
        name: "where-is-my-friends",
        displayName: i18n("where_is_my_friends.title"),
        href: "/where-is-my-friends",
        customHref: () => "/where-is-my-friends",
        forceActive: (_category, _args, router) =>
          router.currentRouteName?.startsWith("where-is-my-friends"),
      });

      api.addSaveableUserOption("where_is_my_friends_notify_city", {
        page: "notifications",
      });
    });
  },
};
