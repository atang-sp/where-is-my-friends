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

    server.post("/where-is-my-friends/locations.json", (request) => {
      if (state.saveError) {
        return helper.response(422, { errors: [state.saveError] });
      }

      const location = Object.fromEntries(new URLSearchParams(request.requestBody));
      state.savedLocations.push(location);

      return helper.response({
        state: "ready",
        location: {
          city: location.city || "上海",
          region: location.region || "",
          discovery_mode: location.discovery_mode || "city",
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
  let originalGeolocation;

  needs.hooks.beforeEach(() => {
    originalGeolocation = Object.getOwnPropertyDescriptor(
      navigator,
      "geolocation"
    );
    Object.assign(api, {
      initial: null,
      nearby: null,
      saveError: null,
      events: [],
      nearbyRequests: 0,
      savedLocations: [],
    });
  });

  needs.hooks.afterEach(() => {
    if (originalGeolocation) {
      Object.defineProperty(navigator, "geolocation", originalGeolocation);
    } else {
      delete navigator.geolocation;
    }
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

  test("GPS upgrades city mode without exposing coordinates in the page", async function (assert) {
    api.initial = readyState();
    setGeolocation((success) =>
      success({ coords: { latitude: 31.2304, longitude: 121.4737, accuracy: 18 } })
    );

    await visit("/where-is-my-friends");
    await click("[data-test-advanced-location]");
    await click("[data-test-use-gps]");

    assert.strictEqual(api.savedLocations.length, 1);
    assert.strictEqual(api.savedLocations[0].discovery_mode, "gps");
    assert.strictEqual(api.savedLocations[0].city, "上海");
    assert.dom("[data-test-precise-coordinates]").doesNotExist();
  });

  test("GPS denial keeps the city fallback active", async function (assert) {
    api.initial = readyState();
    setGeolocation((_success, failure) => failure({ code: 1 }));

    await visit("/where-is-my-friends");
    await click("[data-test-advanced-location]");
    await click("[data-test-use-gps]");

    assert.strictEqual(api.savedLocations.length, 0);
    assert.dom("[data-test-gps-fallback]").exists();
    assert.dom("[data-test-location-mode='city']").exists();
  });

  test("map mode falls back to OSM without a provider key and never reverse geocodes", async function (assert) {
    api.initial = readyState({ map_provider: "amap" });

    await visit("/where-is-my-friends");
    await click("[data-test-advanced-location]");
    await click("[data-test-use-map]");

    assert.dom("[data-test-map-provider]").hasText("OpenStreetMap");
    await fillIn("[data-test-map-latitude]", "31.2304");
    await fillIn("[data-test-map-longitude]", "121.4737");
    await click("[data-test-confirm-map]");

    assert.strictEqual(api.savedLocations.length, 1);
    assert.strictEqual(api.savedLocations[0].discovery_mode, "map");
    assert.strictEqual(api.savedLocations[0].latitude, "31.2304");
    assert.strictEqual(api.savedLocations[0].longitude, "121.4737");
  });
});

function readyState(settings = {}) {
  return {
    state: "ready",
    current_user: { id: 1, username: "current-user" },
    location: { city: "上海", region: "", discovery_mode: "city" },
    active_participants: { suppressed: true },
    city_suggestions: [],
    settings: {
      location_ttl_days: 30,
      virtual_location_enabled: true,
      map_provider: "openstreetmap",
      ...settings,
    },
  };
}

function setGeolocation(getCurrentPosition) {
  Object.defineProperty(navigator, "geolocation", {
    configurable: true,
    value: { getCurrentPosition },
  });
}
