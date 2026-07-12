import { click, fillIn, triggerEvent, visit, waitFor } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const CALLOUT_STORAGE_KEY = "local-friends-callout-state";

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
          settings: {},
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
          discovery_radius_km: Number(location.discovery_radius_km || 100),
        },
      });
    });

    server.get("/where-is-my-friends/locations/nearby.json", () => {
      if (state.nearbyError) {
        return helper.response(500, { errors: [] });
      }

      state.nearbyRequests += 1;
      return helper.response(state.nearby ?? { state: "empty", users: [] });
    }, state.nearbyDelay);

    server.delete("/where-is-my-friends/locations.json", () => {
      state.deleteRequests += 1;
      return helper.response({ success: "OK", state: "setup" });
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
  let originalClipboard;

  needs.hooks.beforeEach(() => {
    localStorage.removeItem(CALLOUT_STORAGE_KEY);
    originalGeolocation = Object.getOwnPropertyDescriptor(
      navigator,
      "geolocation"
    );
    originalClipboard = Object.getOwnPropertyDescriptor(navigator, "clipboard");
    Object.assign(api, {
      initial: null,
      nearby: null,
      saveError: null,
      events: [],
      nearbyRequests: 0,
      nearbyDelay: 0,
      nearbyError: false,
      savedLocations: [],
      deleteRequests: 0,
    });
  });

  needs.hooks.afterEach(() => {
    localStorage.removeItem(CALLOUT_STORAGE_KEY);
    if (originalGeolocation) {
      Object.defineProperty(navigator, "geolocation", originalGeolocation);
    } else {
      delete navigator.geolocation;
    }
    if (originalClipboard) {
      Object.defineProperty(navigator, "clipboard", originalClipboard);
    } else {
      delete navigator.clipboard;
    }
  });

  setupApi(needs, api);

  test("topic lists introduce city discovery with privacy-safe social proof", async function (assert) {
    api.initial = {
      state: "setup",
      current_user: { id: 1, username: "current-user" },
      location: null,
      active_participants: { suppressed: false, count: 12 },
      city_suggestions: [],
      settings: {},
    };

    await visit("/");

    assert.dom("[data-test-local-friends-callout]").exists();
    assert
      .dom("[data-test-local-friends-callout-proof]")
      .hasText("12 members are already participating");
    assert.dom("[data-test-local-friends-callout-setup]").exists();
    assert.dom("[data-test-callout-city-input]").exists();
    assert.dom("[data-test-callout-save-city]").exists();
  });

  test("topic-list callout uses generic proof below the privacy threshold", async function (assert) {
    await visit("/");

    assert
      .dom("[data-test-local-friends-callout-proof]")
      .hasText("Local members are already participating");
  });

  test("topic-list callout can save a city inline without leaving the page", async function (assert) {
    await visit("/");

    await fillIn("[data-test-callout-city-input]", "上海");
    await click("[data-test-callout-save-city]");

    assert.strictEqual(api.savedLocations.length, 1);
    assert.strictEqual(api.savedLocations[0].city, "上海");
    assert
      .dom("[data-test-local-friends-callout-cta]")
      .hasText("View local members")
      .hasAttribute("href", "/where-is-my-friends");
  });

  test("returning users can dismiss the topic-list callout with local persistence", async function (assert) {
    api.initial = readyState();

    await visit("/");

    assert
      .dom("[data-test-local-friends-callout-cta]")
      .hasText("View local members");
    await click("[data-test-dismiss-local-friends]");
    assert.dom("[data-test-local-friends-callout]").doesNotExist();

    await visit("/latest");
    assert.dom("[data-test-local-friends-callout]").doesNotExist();
    assert.ok(localStorage.getItem(CALLOUT_STORAGE_KEY));
  });

  test("topic-list callout is not duplicated on the Local Friends page", async function (assert) {
    await visit("/where-is-my-friends");

    assert.dom("[data-test-local-friends-callout]").doesNotExist();
    assert.dom(".where-is-my-friends").exists();
  });

  test("setup uses social proof, city suggestions, and an optional region", async function (assert) {
    api.initial = {
      state: "setup",
      current_user: { id: 1, username: "current-user" },
      location: null,
      active_participants: { suppressed: false, count: 12 },
      city_suggestions: [
        { city: "上海", city_key: "上海" },
        { city: "北京", city_key: "北京" },
      ],
      settings: {},
    };

    await visit("/where-is-my-friends");

    assert
      .dom("[data-test-participant-proof]")
      .hasText("12 members have joined local discovery");
    assert
      .dom("[data-test-city-input]")
      .hasAttribute("list", "where-is-my-friends-city-suggestions");
    assert
      .dom("#where-is-my-friends-city-suggestions option")
      .exists({ count: 2 });
    assert.dom("[data-test-region-field]").doesNotExist();

    await click("[data-test-toggle-region]");
    assert.dom("[data-test-region-field]").exists();
    await fillIn("[data-test-city-input]", "上海");
    await fillIn("[data-test-region-field]", "上海");
    await click("[data-test-save-city]");

    assert.strictEqual(api.savedLocations[0].region, "上海");
  });

  test("editing a saved region keeps the optional field visible", async function (assert) {
    api.initial = readyState();
    api.initial.location.region = "上海";

    await visit("/where-is-my-friends");
    await click("[data-test-update-location]");

    assert.dom("[data-test-region-field]").hasValue("上海");
    assert.dom("[data-test-toggle-region]").doesNotExist();
  });

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
      },
      active_participants: { suppressed: false, count: 12 },
      city_suggestions: [],
      settings: {},
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
      settings: {},
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

  test("generic discovery failures use translated recovery copy", async function (assert) {
    api.initial = readyState();
    api.nearbyError = true;

    await visit("/where-is-my-friends");

    assert
      .dom("[data-test-error]")
      .hasText("We couldn't load local discovery. Please try again.");
  });

  test("loading results shows temporary member-card skeletons", async function (assert) {
    api.nearbyDelay = 250;

    await visit("/where-is-my-friends");
    await fillIn("[data-test-city-input]", "上海");
    const save = click("[data-test-save-city]");

    await waitFor("[data-test-result-skeleton]");
    assert.dom("[data-test-result-skeleton]").exists({ count: 3 });
    await save;
    assert.dom("[data-test-result-skeleton]").doesNotExist();
  });

  test("the current user is not rendered even if returned defensively", async function (assert) {
    api.initial = {
      state: "ready",
      current_user: { id: 1, username: "current-user" },
      location: { city: "上海", discovery_mode: "city" },
      active_participants: { suppressed: true },
      city_suggestions: [],
      settings: {},
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

  test("connection links are safe, actionable, and measured", async function (assert) {
    api.initial = readyState();
    api.nearby = { state: "ready", users: [localUser("alice", "Alice")] };

    await visit("/where-is-my-friends");

    assert
      .dom("[data-test-results-summary]")
      .hasText("1 member within 100 km of 上海");
    assert.dom("[data-test-profile-link='alice']").hasAttribute("href", "/u/alice");
    assert
      .dom("[data-test-profile-link='alice']")
      .doesNotHaveClass("btn-primary");
    assert
      .dom("[data-test-profile-link='alice']")
      .hasAttribute("aria-label", "View alice's profile");
    assert
      .dom("[data-test-message-link='alice']")
      .hasAttribute("href", "/new-message?username=alice");
    assert
      .dom("[data-test-message-link='alice']")
      .hasAttribute("aria-label", "Send a message to alice")
      .hasClass("btn-primary");
    assert
      .dom("[data-test-local-topics]")
      .hasAttribute("href", "/search?q=%E4%B8%8A%E6%B5%B7");
    await triggerEvent("[data-test-profile-link='alice']", "click", {
      ctrlKey: true,
    });
    await triggerEvent("[data-test-message-link='alice']", "click", {
      ctrlKey: true,
    });
    await triggerEvent("[data-test-local-topics]", "click", { ctrlKey: true });

    assert.true(api.events.includes("profile_clicked"));
    assert.true(api.events.includes("message_started"));
    assert.true(api.events.includes("local_topics_clicked"));
    assert.dom("[data-test-member-filter]").doesNotExist();
  });

  test("filters appear only for ten or more results and filter by name", async function (assert) {
    api.initial = readyState();
    api.nearby = {
      state: "ready",
      users: [
        localUser("alice", "Alice"),
        ...Array.from({ length: 10 }, (_value, index) =>
          localUser(`member-${index}`, `Member ${index}`)
        ),
      ],
    };

    await visit("/where-is-my-friends");
    assert.dom("[data-test-member-filter]").exists();
    assert
      .dom("[data-test-member-filter]")
      .hasAttribute("aria-label", "Filter members");
    await fillIn("[data-test-member-filter]", "alice");

    assert.dom("[data-test-user-card='alice']").exists();
    assert.dom("[data-test-user-card='member-0']").doesNotExist();
  });

  test("update and removal controls are visible and removal is measured", async function (assert) {
    api.initial = readyState();

    await visit("/where-is-my-friends");

    assert.dom("[data-test-location-settings-toggle]").hasText("Location settings");
    assert.dom("[data-test-location-settings]").exists();
    assert.dom("[data-test-location-settings]").doesNotHaveAttribute("open");

    await click("[data-test-location-settings-toggle]");
    assert.dom("[data-test-location-settings]").hasAttribute("open");
    await click("[data-test-update-location]");
    assert.dom("[data-test-city-input]").hasValue("上海");

    await click("[data-test-save-city]");
    await click("[data-test-location-settings-toggle]");
    await click("[data-test-remove-location]");
    assert.strictEqual(api.deleteRequests, 1);
    assert.dom("[data-test-city-input]").exists();
    assert.true(api.events.includes("location_removed"));
  });

  test("empty state offers local topics and measures the click", async function (assert) {
    api.initial = readyState();

    await visit("/where-is-my-friends");

    assert
      .dom("[data-test-local-topics]")
      .hasAttribute("href", "/search?q=%E4%B8%8A%E6%B5%B7");
    assert
      .dom("[data-test-local-topics]")
      .hasAttribute("aria-label", "Browse topics about 上海");
    await triggerEvent("[data-test-local-topics]", "click", { ctrlKey: true });
    assert.true(api.events.includes("local_topics_clicked"));
    assert.dom("[data-test-empty-invitation]").exists();
  });

  test("empty state copies an invite link and announces the outcome", async function (assert) {
    api.initial = readyState();
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: () => Promise.resolve() },
    });

    await visit("/where-is-my-friends");
    await click("[data-test-copy-invite]");

    assert
      .dom("[data-test-invite-feedback]")
      .hasText("Invite link copied to your clipboard");
  });

  test("empty state explains when copying an invite link fails", async function (assert) {
    api.initial = readyState();
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: () => Promise.reject() },
    });

    await visit("/where-is-my-friends");
    await click("[data-test-copy-invite]");

    assert
      .dom("[data-test-invite-feedback]")
      .hasText("Could not copy the invite link. Please try again.");
  });

  test("results show a NEW badge and bio excerpt for recent members", async function (assert) {
    api.initial = readyState();
    api.nearby = {
      state: "ready",
      users: [
        {
          ...localUser("alice", "Alice"),
          is_recent: true,
          bio_excerpt: "Weekend cyclist and tea drinker.",
        },
      ],
    };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-new-member-badge]").hasText("NEW");
    assert
      .dom("[data-test-user-bio]")
      .hasText("Weekend cyclist and tea drinker.");
  });

  test("discovery radius can be changed and reloads nearby results", async function (assert) {
    api.initial = readyState();
    api.nearby = { state: "ready", users: [localUser("alice", "Alice")] };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-discovery-radius]").exists();
    assert.dom("[data-test-discovery-radius-option='100']").hasClass("btn-primary");

    await click("[data-test-discovery-radius-option='200']");

    assert.strictEqual(api.savedLocations.length, 1);
    assert.strictEqual(api.savedLocations[0].discovery_radius_km, "200");
    assert.strictEqual(api.nearbyRequests, 2);
    assert
      .dom("[data-test-results-summary]")
      .hasText("1 member within 200 km of 上海");
  });
});

function readyState(settings = {}) {
  return {
    state: "ready",
    current_user: { id: 1, username: "current-user" },
    location: {
      city: "上海",
      region: "",
      discovery_mode: "city",
      discovery_radius_km: 100,
    },
    active_participants: { suppressed: true },
    city_suggestions: [],
    settings: {
      virtual_location_enabled: true,
      map_provider: "openstreetmap",
      default_discovery_radius_km: 100,
      discovery_radius_options_km: [50, 100, 200],
      ...settings,
    },
  };
}

function localUser(username, name) {
  return {
    id: username,
    username,
    name,
    avatar_template: `/user_avatar/localhost/${username}/{size}/1.png`,
    city: "上海",
    discovery_mode: "city",
    distance_band: null,
    profile_url: `/u/${username}`,
    message_url: `/new-message?username=${username}`,
    local_topics_url: "/search?q=%E4%B8%8A%E6%B5%B7",
  };
}

function setGeolocation(getCurrentPosition) {
  Object.defineProperty(navigator, "geolocation", {
    configurable: true,
    value: { getCurrentPosition },
  });
}
