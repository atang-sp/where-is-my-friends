import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import customActionNotificationRenderer from "discourse/plugins/where-is-my-friends/discourse/lib/custom-action-notification-renderer";

export default {
  name: "where-is-my-friends",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.where_is_my_friends_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.registerNotificationTypeRenderer(
        "custom",
        customActionNotificationRenderer
      );

      api.addCommunitySectionLink({
        name: "where-is-my-friends",
        route: "where-is-my-friends",
        title: i18n("where_is_my_friends.title"),
        text: i18n("where_is_my_friends.title"),
        icon: "location-dot",
      });

      if (siteSettings.where_is_my_friends_interest_onboarding_enabled) {
        api.addCommunitySectionLink({
          name: "where-is-my-friends-interests",
          route: "where-is-my-friends-interests",
          title: i18n("where_is_my_friends.interests.sidebar_title"),
          text: i18n("where_is_my_friends.interests.sidebar_title"),
          icon: "sparkles",
        });
      }

      api.addSaveableUserOption("where_is_my_friends_notify_city", {
        page: "notifications",
      });
      api.addSaveableUserOption("where_is_my_friends_notify_nearby", {
        page: "notifications",
      });
      api.addSaveableUserOption(
        "where_is_my_friends_accept_practice_invitations",
        { page: "notifications" }
      );
    });
  },
};
