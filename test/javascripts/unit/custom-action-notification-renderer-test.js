import { module, test } from "qunit";
import customActionNotificationRenderer from "discourse/plugins/where-is-my-friends/discourse/lib/custom-action-notification-renderer";

module("Unit | Local Friends custom action notification renderer", function () {
  class NotificationTypeBase {
    constructor(notification) {
      this.notification = notification;
    }

    get linkHref() {
      return "/core-link";
    }
  }

  const Renderer = customActionNotificationRenderer(NotificationTypeBase);

  test("uses a custom action URL when one is present", function (assert) {
    const renderer = new Renderer({
      data: {
        action_url: "/where-is-my-friends/interests",
        message: "where_is_my_friends.practice_invitations.notification_message",
      },
    });

    assert.strictEqual(
      renderer.linkHref,
      "/where-is-my-friends/interests"
    );
  });

  test("keeps the legacy matching action URL during the overlap release", function (assert) {
    const renderer = new Renderer({
      data: {
        action_url: "/practice-matching",
        message: "practice_matching.notification.mutual_match",
      },
    });

    assert.strictEqual(renderer.linkHref, "/practice-matching");
  });

  test("preserves core link behavior for unrelated custom notifications", function (assert) {
    const renderer = new Renderer({
      data: {
        action_url: "/another-plugin",
        message: "another.plugin.notification",
      },
    });

    assert.strictEqual(renderer.linkHref, "/core-link");
  });
});
