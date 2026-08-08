import { getOwner } from "@ember/owner";
import {
  click,
  currentURL,
  find,
  settled,
  visit,
  waitFor,
} from "@ember/test-helpers";
import { test } from "qunit";
import { defaultHomepage, setDefaultHomepage } from "discourse/lib/utilities";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";
import { FIRST_CONNECTION_COOLDOWN_KEY } from "discourse/plugins/where-is-my-friends/discourse/lib/first-connection-cooldown";

function topicAction() {
  return {
    state: "topic",
    title_key: "where_is_my_friends.first_connection.topic.title",
    description_key: "where_is_my_friends.first_connection.topic.description",
    primary_action: {
      kind: "open_topic",
      label_key: "where_is_my_friends.first_connection.topic.cta",
      url: "/t/a-visible-topic/42",
    },
    secondary_action: {
      kind: "open_recommendations",
      label_key: "where_is_my_friends.first_connection.more",
      url: "/where-is-my-friends/interests",
    },
    recommendation_group: "topics",
    algorithm_version: "first_connection_v1",
  };
}

async function triggerTrackedLink(selector) {
  const element = find(selector);
  const event = new element.ownerDocument.defaultView.MouseEvent("click", {
    bubbles: true,
    cancelable: true,
  });
  event.preventDefault();
  element.dispatchEvent(event);
  await settled();
}

acceptance("Where Is My Friends | first connection", function (needs) {
  needs.settings({
    where_is_my_friends_enabled: true,
    where_is_my_friends_first_connection_enabled: true,
    where_is_my_friends_interest_onboarding_enabled: true,
  });
  needs.user({
    username: "current-user",
    where_is_my_friends_interest_onboarding_state: "complete",
  });

  const api = {};

  needs.hooks.beforeEach(() => {
    localStorage.removeItem(FIRST_CONNECTION_COOLDOWN_KEY);
    Object.assign(api, {
      originalHomepage: defaultHomepage(),
      response: topicAction(),
      responseStatus: 200,
      defer: false,
      resolve: null,
      requests: 0,
      events: [],
      eventPayloads: [],
      eventStatus: 200,
    });
  });

  needs.hooks.afterEach(() => {
    localStorage.removeItem(FIRST_CONNECTION_COOLDOWN_KEY);
    setDefaultHomepage(api.originalHomepage);
  });

  needs.pretender((server, helper) => {
    server.get("/where-is-my-friends/callout.json", () =>
      helper.response({
        state: "setup",
        current_user: { id: 1, username: "current-user" },
        location: null,
        active_participants: { suppressed: true },
        city_suggestions: [],
        settings: {},
        filterable_fields: [],
      })
    );

    server.get("/where-is-my-friends/next-action.json", () => {
      api.requests += 1;
      if (api.defer) {
        return new Promise((resolve) => {
          api.resolve = () =>
            resolve(helper.response(api.responseStatus, api.response));
        });
      }
      return helper.response(api.responseStatus, api.response);
    });

    server.post("/where-is-my-friends/events.json", (request) => {
      const payload = new URLSearchParams(request.requestBody);
      api.events.push(payload.get("event_name"));
      api.eventPayloads.push(payload);
      return helper.response(api.eventStatus, {
        success: api.eventStatus === 200 ? "OK" : undefined,
      });
    });
  });

  test("shows a compact loading state before one action", async function (assert) {
    api.defer = true;

    const navigation = visit("/");
    await waitFor("[data-test-first-connection-loading]");

    assert
      .dom("[data-test-first-connection-loading]")
      .hasAttribute("aria-busy", "true");
    assert.dom("[data-test-first-connection-card]").doesNotExist();

    api.resolve();
    await navigation;

    assert.dom("[data-test-first-connection-loading]").doesNotExist();
    assert.dom("[data-test-first-connection-card]").exists({ count: 1 });
  });

  test("renders one accessible action and records one target-free view", async function (assert) {
    await visit("/");

    assert
      .dom("[data-test-first-connection-card]")
      .hasClass("first-connection-card")
      .hasAttribute("data-state", "topic")
      .includesText("Start with a discussion that's easy to join");
    assert
      .dom("[data-test-first-connection-primary]")
      .hasAttribute("href", "/t/a-visible-topic/42")
      .hasText("Join the discussion");
    assert
      .dom("[data-test-first-connection-secondary]")
      .hasAttribute("href", "/where-is-my-friends/interests")
      .hasText("See more recommendations");
    assert
      .dom("[data-test-first-connection-actions]")
      .hasClass("first-connection-card__actions");
    assert
      .dom("[data-test-dismiss-first-connection]")
      .hasAttribute(
        "aria-label",
        "Hide today's suggested action for seven days"
      );
    assert.dom("[data-test-community-discovery]").doesNotExist();
    assert.dom("[data-test-local-friends-callout]").doesNotExist();
    assert.dom("[data-test-personal-dynamics-homepage]").doesNotExist();
    assert.deepEqual(api.events, ["first_connection_card_viewed"]);
    assert.strictEqual(api.eventPayloads[0].get("surface"), "homepage");
    assert.strictEqual(
      api.eventPayloads[0].get("algorithm_version"),
      "first_connection_v1"
    );
    assert.strictEqual(
      api.eventPayloads[0].get("recommendation_group"),
      "topics"
    );
    assert.strictEqual(api.eventPayloads[0].get("topic_id"), null);

    await settled();
    assert.strictEqual(
      api.events.filter((name) => name === "first_connection_card_viewed")
        .length,
      1
    );

    await triggerTrackedLink("[data-test-first-connection-primary]");
    await triggerTrackedLink("[data-test-first-connection-secondary]");
    assert.true(api.events.includes("first_connection_topic_opened"));
    assert.true(api.events.includes("first_connection_recommendations_opened"));
  });

  test("an empty response leaves no homepage gap", async function (assert) {
    api.response = { state: "empty", algorithm_version: "first_connection_v1" };
    await visit("/");

    assert.dom("[data-test-first-connection-loading]").doesNotExist();
    assert.dom("[data-test-first-connection-card]").doesNotExist();
    assert.dom("[data-test-community-discovery]").exists();
    assert.deepEqual(api.events, []);
  });

  test("an API error leaves no homepage gap", async function (assert) {
    api.responseStatus = 500;
    await visit("/");

    assert.dom("[data-test-first-connection-loading]").doesNotExist();
    assert.dom("[data-test-first-connection-card]").doesNotExist();
    assert.dom("[data-test-community-discovery]").exists();
  });

  test("dismisses locally without saving target content", async function (assert) {
    await visit("/");
    await click("[data-test-dismiss-first-connection]");

    assert.dom("[data-test-first-connection-card]").doesNotExist();
    assert.dom("[data-test-community-discovery]").exists();
    assert.true(api.events.includes("first_connection_card_dismissed"));
    assert.true(
      Number.isFinite(
        Number(localStorage.getItem(FIRST_CONNECTION_COOLDOWN_KEY))
      )
    );
    assert.false(
      localStorage
        .getItem(FIRST_CONNECTION_COOLDOWN_KEY)
        .includes("a-visible-topic")
    );
  });

  test("telemetry failure does not block primary navigation", async function (assert) {
    api.response = {
      ...topicAction(),
      state: "local_discovery",
      title_key: "where_is_my_friends.first_connection.local_discovery.title",
      description_key:
        "where_is_my_friends.first_connection.local_discovery.description",
      primary_action: {
        kind: "open_local_discovery",
        label_key: "where_is_my_friends.first_connection.local_discovery.cta",
        url: "/categories",
      },
      secondary_action: null,
      recommendation_group: null,
    };
    api.eventStatus = 500;
    await visit("/");

    await click("[data-test-first-connection-primary]");

    assert.strictEqual(currentURL(), "/categories");
    assert.true(api.events.includes("first_connection_local_opened"));
  });

  test("the feature setting disables the new card and its request", async function (assert) {
    getOwner(this).lookup(
      "service:site-settings"
    ).where_is_my_friends_first_connection_enabled = false;

    await visit("/");

    assert.dom("[data-test-first-connection-loading]").doesNotExist();
    assert.dom("[data-test-first-connection-card]").doesNotExist();
    assert.dom("[data-test-community-discovery]").exists();
    assert.strictEqual(api.requests, 0);
  });

  test("renders on a categories-configured homepage", async function (assert) {
    setDefaultHomepage("categories");

    await visit("/");

    assert.dom("[data-test-first-connection-card]").exists({ count: 1 });
    assert.strictEqual(api.requests, 1);
  });
});
