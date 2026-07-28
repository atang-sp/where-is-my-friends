import { i18n } from "discourse-i18n";

const ACTION_MESSAGES = new Set([
  "where_is_my_friends.practice_invitations.notification_message",
  "practice_matching.notification.mutual_match",
]);

export default function customActionNotificationRenderer(
  NotificationTypeBase
) {
  return class extends NotificationTypeBase {
    get linkHref() {
      if (
        ACTION_MESSAGES.has(this.notification.data.message) &&
        this.notification.data.action_url
      ) {
        return this.notification.data.action_url;
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
