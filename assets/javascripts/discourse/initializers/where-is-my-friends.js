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
        icon: "map-marker-alt",
      });

      api.addSaveableUserOption("where_is_my_friends_notify_city", {
        page: "notifications",
      });

      api.registerNotificationTypeRenderer(
        "custom",
        (NotificationTypeBase) => {
          return class extends NotificationTypeBase {
            get linkTitle() {
              if (this.notification.data.title) {
                return i18n(this.notification.data.title);
              }
              return super.linkTitle;
            }

            get icon() {
              if (this.isLocalFriendsNotification) {
                return "map-marker-alt";
              }
              return `notification.${this.notification.data.message}`;
            }

            get linkHref() {
              if (this.isLocalFriendsNotification) {
                return "/where-is-my-friends";
              }
              return super.linkHref;
            }

            get isLocalFriendsNotification() {
              return (
                this.notification.data.message ===
                "where_is_my_friends.notification.member_joined"
              );
            }
          };
        }
      );
    });
  },
};
