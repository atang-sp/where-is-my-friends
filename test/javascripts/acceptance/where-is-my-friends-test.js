import { click, fillIn, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

function setupApi(needs, state) {
  needs.pretender((server, helper) => {
    server.get("/where-is-my-friends.json", () =>
      helper.response(
        state.initial ?? {
          state: "setup",
          current_user: { id: 1, username: "current-user" },
          location: null,
          active_participants: { suppressed: true },
          city_suggestions: [],
          settings: { location_ttl_days: 30 },
        }
      )
    );

    server.post("/where-is-my-friends/locations.json", () => {
      if (state.saveError) {
        return helper.response(422, { errors: [state.saveError] });
      }

      return helper.response({
        state: "ready",
        location: {
          city: "上海",
          region: "",
          discovery_mode: "city",
          expires_at: "2026-08-10T12:00:00Z",
        },
      });
    });

    server.get("/where-is-my-friends/locations/nearby.json", () => {
      state.nearbyRequests += 1;
      return helper.response(state.nearby ?? { state: "empty", users: [] });
    });

    server.post("/where-is-my-friends/events.json", (request) => {
      state.events.push(
        new URLSearchParams(request.requestBody).get("event_name")
      );
      return helper.response({ success: "OK" });
    });
  });
}

acceptance("Where Is My Friends | city discovery", function (needs) {
  needs.user({ username: "current-user" });
  const api = {};

  needs.hooks.beforeEach(() => {
    Object.assign(api, {
      initial: null,
      nearby: null,
      saveError: null,
      events: [],
      nearbyRequests: 0,
    });
  });

  setupApi(needs, api);

  test("first visit saves a city and automatically loads results", async function (assert) {
    api.nearby = {
      state: "ready",
      users: [
        {
          id: 2,
          username: "alice",
          name: "Alice",
          avatar_template: "/user_avatar/localhost/alice/{size}/1.png",
          city: "上海",
          discovery_mode: "city",
          distance_band: null,
          profile_url: "/u/alice",
          message_url: "/new-message?username=alice",
          local_topics_url: "/search?q=%E4%B8%8A%E6%B5%B7",
        },
      ],
    };

    await visit("/where-is-my-friends");
    await fillIn("[data-test-city-input]", "上海");
    await click("[data-test-save-city]");

    assert.dom("[data-test-user-card='alice']").exists();
    assert.strictEqual(api.nearbyRequests, 1);
    assert.true(api.events.includes("setup_started"));
    assert.true(api.events.includes("location_saved"));
    assert.true(api.events.includes("results_viewed"));
  });

  test("returning visit loads results without a find button", async function (assert) {
    api.initial = {
      state: "ready",
      current_user: { id: 1, username: "current-user" },
      location: {
        city: "上海",
        discovery_mode: "city",
        expires_at: "2026-08-10T12:00:00Z",
      },
      active_participants: { suppressed: false, count: 12 },
      city_suggestions: [],
      settings: { location_ttl_days: 30 },
    };
    api.nearby = { state: "empty", users: [] };

    await visit("/where-is-my-friends");

    assert.strictEqual(api.nearbyRequests, 1);
    assert.dom("[data-test-find-nearby]").doesNotExist();
    assert.dom("[data-test-empty-state]").exists();
  });

  test("empty results render an actionable state", async function (assert) {
    api.initial = {
      state: "ready",
      current_user: { id: 1, username: "current-user" },
      location: { city: "成都", discovery_mode: "city" },
      active_participants: { suppressed: true },
      city_suggestions: [],
      settings: { location_ttl_days: 30 },
    };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-empty-state]").exists();
    assert.dom("[data-test-local-topics]").exists();
  });

  test("server errors are rendered as escaped plain text", async function (assert) {
    api.saveError = '<img src=x onerror="alert(1)">';

    await visit("/where-is-my-friends");
    await fillIn("[data-test-city-input]", "上海");
    await click("[data-test-save-city]");

    assert.dom("[data-test-error]").hasText('<img src=x onerror="alert(1)">');
    assert.dom("[data-test-error] img").doesNotExist();
  });

  test("the current user is not rendered even if returned defensively", async function (assert) {
    api.initial = {
      state: "ready",
      current_user: { id: 1, username: "current-user" },
      location: { city: "上海", discovery_mode: "city" },
      active_participants: { suppressed: true },
      city_suggestions: [],
      settings: { location_ttl_days: 30 },
    };
    api.nearby = {
      state: "ready",
      users: [
        { id: 1, username: "current-user", city: "上海" },
        { id: 2, username: "alice", city: "上海", profile_url: "/u/alice" },
      ],
    };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-user-card='current-user']").doesNotExist();
    assert.dom("[data-test-user-card='alice']").exists();
  });
});
