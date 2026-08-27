import { i18n } from "discourse-i18n";

const ACTION_MESSAGES = new Set([
  "where_is_my_friends.practice_invitations.notification_message",
  "where_is_my_friends.user_tags.notification_message",
  "practice_matching.notification.mutual_match",
]);

const DYNAMIC_REACTION_MESSAGE_PREFIX =
  "where_is_my_friends.dynamics.reaction_notifications.";

export default function customActionNotificationRenderer(NotificationTypeBase) {
  return class extends NotificationTypeBase {
    get linkHref() {
      if (
        (ACTION_MESSAGES.has(this.notification.data.message) ||
          this.notification.data.message?.startsWith(
            DYNAMIC_REACTION_MESSAGE_PREFIX
          )) &&
        this.notification.data.action_url
      ) {
        return this.notification.data.action_url;
      }

      if (this.notification.data.where_is_my_friends) {
        const source =
          this.notification.data.notification_source ?? "notification";
        return `/where-is-my-friends?notification=${encodeURIComponent(
          source
        )}`;
      }

      return super.linkHref;
    }

    get linkTitle() {
      if (this.notification.data.title) {
        return i18n(this.notification.data.title);
      }
    }

    get icon() {
      return `notification.${this.notification.data.message}`;
    }
  };
}
