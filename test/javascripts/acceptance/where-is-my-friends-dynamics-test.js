import { getOwner } from "@ember/owner";
import { click, currentURL, fillIn, visit } from "@ember/test-helpers";
import { test } from "qunit";
import emojiPicker from "discourse/tests/helpers/emoji-picker-helper";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

function dynamic(id, text = `Dynamic ${id}`) {
  return {
    id,
    url: `/t/dynamic-${id}/${id}`,
    cooked: `<p>${text}</p>`,
    excerpt: text,
    created_at: "2026-08-03T12:00:00.000Z",
    reply_count: 0,
    author: {
      id: 1,
      username: "current-user",
      name: "Current User",
      profile_url: "/u/current-user",
      dynamics_url: "/u/current-user/activity/dynamics",
      avatar_template: "/letter_avatar_proxy/v4/letter/c/1.png",
    },
  };
}

acceptance("Where Is My Friends | personal dynamics", function (needs) {
  needs.settings({
    where_is_my_friends_enabled: true,
    where_is_my_friends_dynamics_enabled: true,
    where_is_my_friends_dynamics_feed_enabled: true,
    where_is_my_friends_dynamics_category_id: 1,
    enable_emoji: true,
  });
  needs.user();

  const api = {};

  needs.hooks.beforeEach(() => {
    Object.assign(api, {
      feedRequests: [],
      homepageFeedRequests: [],
      publishRequests: [],
      events: [],
      publishError: null,
    });
  });

  needs.pretender((server, helper) => {
    server.get("/where-is-my-friends.json", () =>
      helper.response({
        state: "setup",
        current_user: { id: 1, username: "current-user" },
        location: null,
        active_participants: { suppressed: true },
        city_suggestions: [],
        settings: {},
        filterable_fields: [],
      }),
    );

    server.get("/where-is-my-friends/dynamics.json", (request) => {
      api.feedRequests.push(request.queryParams);
      if (request.queryParams.before_id) {
        return helper.response({
          dynamics: [dynamic(1, "The older update")],
          has_more: false,
          before_id: null,
        });
      }
      return helper.response({
        dynamics: [dynamic(2, "A safe link: https://example.com")],
        has_more: true,
        before_id: 2,
      });
    });

    server.get("/where-is-my-friends/dynamics/feed.json", (request) => {
      api.homepageFeedRequests.push(request.queryParams);
      return helper.response({
        dynamics: [dynamic(4, "A member shared a small win")],
        has_more: false,
        before_id: null,
      });
    });

    server.post("/where-is-my-friends/dynamics.json", (request) => {
      const params = new URLSearchParams(request.requestBody);
      api.publishRequests.push(params);
      if (api.publishError) {
        return helper.response(422, { errors: [api.publishError] });
      }
      return helper.response({ dynamic: dynamic(3, params.get("raw")) });
    });

    server.post("/where-is-my-friends/events.json", (request) => {
      api.events.push(new URLSearchParams(request.requestBody));
      return helper.response({ success: "OK" });
    });
  });

  test("own profile exposes a direct publish-dynamic entry", async function (assert) {
    await visit("/u/eviltrout");

    assert
      .dom("[data-test-profile-publish-dynamic]")
      .hasText("Publish dynamic")
      .hasAttribute("href", "/u/eviltrout/activity/dynamics");
  });

  test("other profiles do not expose the publish-dynamic entry", async function (assert) {
    await visit("/u/charlie");

    assert.dom("[data-test-profile-publish-dynamic]").doesNotExist();
  });

  test("disabled personal dynamics hide the profile entry", async function (assert) {
    getOwner(this).lookup(
      "service:site-settings",
    ).where_is_my_friends_dynamics_enabled = false;

    await visit("/u/eviltrout");

    assert.dom("[data-test-profile-publish-dynamic]").doesNotExist();
  });

  test("self view publishes text, counts characters, and has no upload UI", async function (assert) {
    await visit("/u/eviltrout/activity/dynamics");

    assert.dom("[data-test-personal-dynamics]").exists();
    assert.dom("[data-test-personal-dynamics-publisher]").exists();
    assert.dom(".personal-dynamics__emoji-picker").exists();
    assert
      .dom("[data-test-personal-dynamics-publisher] input[type='file']")
      .doesNotExist();
    assert
      .dom("[data-test-personal-dynamics-input]")
      .doesNotHaveAttribute("maxlength");
    assert.dom("[data-test-personal-dynamics-publish]").isDisabled();

    await click(".personal-dynamics__emoji-picker");
    await emojiPicker().select("grinning");
    assert
      .dom("[data-test-personal-dynamics-input]")
      .hasValue(":grinning:");

    await fillIn("[data-test-personal-dynamics-input]", "1234567");
    assert.dom("[data-test-personal-dynamics-count]").hasText("7/500");
    assert.dom("[data-test-personal-dynamics-publish]").isDisabled();

    await fillIn("[data-test-personal-dynamics-input]", "👨‍👩‍👧‍👦 1234567");
    assert.dom("[data-test-personal-dynamics-count]").hasText("9/500");

    await fillIn("[data-test-personal-dynamics-input]", "👨‍👩‍👧‍👦".repeat(500));
    assert.dom("[data-test-personal-dynamics-count]").hasText("500/500");
    assert.dom("[data-test-personal-dynamics-publish]").isNotDisabled();

    await fillIn("[data-test-personal-dynamics-input]", "**12345678**\n\n");
    assert.dom("[data-test-personal-dynamics-count]").hasText("8/500");

    await fillIn("[data-test-personal-dynamics-input]", "A new update");
    assert.dom("[data-test-personal-dynamics-publish]").isNotDisabled();
    await click("[data-test-personal-dynamics-publish]");

    assert.strictEqual(api.publishRequests.length, 1);
    assert.strictEqual(api.publishRequests[0].get("raw"), "A new update");
    assert.strictEqual(api.publishRequests[0].get("title"), null);
    assert.strictEqual(api.publishRequests[0].get("category"), null);
    assert.dom("[data-test-personal-dynamic='3']").exists();
    assert.dom("[data-test-personal-dynamics-input]").hasValue("");
    assert.dom("[data-test-personal-dynamics-notice]").exists();
  });

  test("a disabled feature redirects without loading or measuring the dynamics page", async function (assert) {
    getOwner(this).lookup(
      "service:site-settings",
    ).where_is_my_friends_dynamics_enabled = false;

    await visit("/u/eviltrout/activity/dynamics");

    assert.notStrictEqual(currentURL(), "/u/eviltrout/activity/dynamics");
    assert.dom("[data-test-personal-dynamics]").doesNotExist();
    assert.strictEqual(api.feedRequests.length, 0);
    assert.strictEqual(api.events.length, 0);
  });

  test("other member view is read-only and manual pagination appends older dynamics", async function (assert) {
    await visit("/u/charlie/activity/dynamics");

    assert.dom("[data-test-personal-dynamics-publisher]").doesNotExist();
    assert.strictEqual(api.feedRequests[0].username, "charlie");
    assert.dom("[data-test-personal-dynamic]").exists({ count: 1 });

    await click("[data-test-personal-dynamics-load-more]");

    assert.strictEqual(api.feedRequests[1].before_id, "2");
    assert.dom("[data-test-personal-dynamic]").exists({ count: 2 });
    assert.dom("[data-test-personal-dynamics-load-more]").doesNotExist();
  });

  test("a rejected publication preserves the draft and recovers", async function (assert) {
    api.publishError = "Images and attachments are not allowed.";
    await visit("/u/eviltrout/activity/dynamics");
    await fillIn(
      "[data-test-personal-dynamics-input]",
      "Today includes an unsafe image ![image](upload://unsafe.png)",
    );
    await click("[data-test-personal-dynamics-publish]");

    assert
      .dom("[data-test-personal-dynamics-error]")
      .hasText("Images and attachments are not allowed.");
    assert
      .dom("[data-test-personal-dynamics-input]")
      .hasValue("Today includes an unsafe image ![image](upload://unsafe.png)");

    api.publishError = null;
    await fillIn("[data-test-personal-dynamics-input]", "Recovered update");
    await click("[data-test-personal-dynamics-publish]");
    assert.dom("[data-test-personal-dynamics-error]").doesNotExist();
    assert.dom("[data-test-personal-dynamic='3']").exists();
  });

  test("the homepage shows a dynamic feed and links to the browse page", async function (assert) {
    await visit("/latest");

    assert.dom("[data-test-personal-dynamics-homepage]").exists();
    assert
      .dom(
        "[data-test-personal-dynamics-homepage] [data-test-personal-dynamic]",
      )
      .exists({ count: 1 });
    assert.strictEqual(api.homepageFeedRequests.length, 1);
    assert
      .dom("[data-test-personal-dynamics-browse]")
      .hasAttribute("href", "/where-is-my-friends/dynamics");
  });

  test("the browse page exposes other members' dynamics with pagination", async function (assert) {
    await visit("/where-is-my-friends/dynamics");

    assert.dom("[data-test-personal-dynamics-feed]").exists();
    assert
      .dom(
        "[data-test-personal-dynamics-feed] [data-test-personal-dynamic-author]",
      )
      .hasText("Current User");
    assert.strictEqual(api.homepageFeedRequests.length, 1);
  });
});
