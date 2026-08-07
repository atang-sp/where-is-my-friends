import { getOwner } from "@ember/owner";
import {
  click,
  fillIn,
  triggerEvent,
  visit,
  waitFor,
} from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const CALLOUT_STORAGE_KEY = "local-friends-callout-state";

function setupApi(needs, state) {
  needs.pretender((server, helper) => {
    server.get("/where-is-my-friends.json", () => {
      state.locationRequests += 1;
      return helper.response(
        state.initial ?? {
          state: "setup",
          current_user: { id: 1, username: "current-user" },
          location: null,
          active_participants: { suppressed: true },
          city_suggestions: [],
          settings: {},
          filterable_fields: [],
        }
      );
    });

    server.post("/where-is-my-friends/locations.json", (request) => {
      if (state.saveError) {
        return helper.response(422, { errors: [state.saveError] });
      }

      const location = Object.fromEntries(
        new URLSearchParams(request.requestBody)
      );
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

    server.get("/where-is-my-friends/cities/preview.json", (request) => {
      state.previewRequests += 1;
      state.lastPreviewParams = request.queryParams;
      return helper.response(
        state.preview ?? {
          city: {
            city: request.queryParams.city,
            city_key: request.queryParams.city,
            canonical: true,
            recent_active_count: 0,
            joined_count: 0,
          },
          radius_options: [],
          recommended_radius_km: null,
          nearby_cities: [],
          local_topics: [],
        }
      );
    });

    server.get(
      "/where-is-my-friends/locations/nearby.json",
      (request) => {
        if (state.nearbyError) {
          return helper.response(500, { errors: [] });
        }

        state.nearbyRequests += 1;
        state.lastNearbyParams = request.queryParams;
        return helper.response(state.nearby ?? { state: "empty", users: [] });
      },
      state.nearbyDelay
    );

    server.delete("/where-is-my-friends/locations.json", () => {
      state.deleteRequests += 1;
      return helper.response({ success: "OK", state: "setup" });
    });

    server.post("/where-is-my-friends/events.json", (request) => {
      const payload = new URLSearchParams(request.requestBody);
      state.events.push(payload.get("event_name"));
      state.eventPayloads.push(payload);
      return helper.response({ success: "OK" });
    });
  });
}

acceptance("Where Is My Friends | city discovery", function (needs) {
  needs.settings({
    chat_enabled: true,
    where_is_my_friends_enabled: true,
    where_is_my_friends_interest_onboarding_enabled: true,
    where_is_my_friends_target_category_id: 1,
    where_is_my_friends_target_category_slug: "legacy-only",
  });
  needs.user({ username: "current-user", has_chat_enabled: true });
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
      eventPayloads: [],
      nearbyRequests: 0,
      locationRequests: 0,
      nearbyDelay: 0,
      nearbyError: false,
      savedLocations: [],
      deleteRequests: 0,
      lastNearbyParams: null,
      preview: null,
      previewRequests: 0,
      lastPreviewParams: null,
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
      city_directory: {
        active: [
          {
            city: "上海",
            city_key: "上海",
            recent_active_count: 3,
            joined_count: 5,
          },
        ],
        growing: [
          {
            city: "上海",
            city_key: "上海",
            recent_active_count: 2,
            joined_count: 4,
          },
          {
            city: "苏州",
            city_key: "苏州",
            recent_active_count: 2,
            joined_count: 4,
          },
        ],
      },
      settings: {},
    };

    await visit("/");

    assert.dom("[data-test-local-friends-callout]").exists();
    assert
      .dom("[data-test-local-friends-callout-proof]")
      .hasText("12 people have joined — are any near you?");
    assert
      .dom("[data-test-callout-city-card='上海']")
      .exists({ count: 1 })
      .includesText("3 active")
      .includesText("5 joined");
    assert.dom("[data-test-callout-city-card='苏州']").exists();
    assert.dom("[data-test-local-friends-callout-setup]").doesNotExist();
    const calloutView = api.eventPayloads.find(
      (payload) => payload.get("event_name") === "local_callout_viewed"
    );
    assert.strictEqual(calloutView?.get("surface"), "homepage");
  });

  test("topic-list callout uses generic proof below the privacy threshold", async function (assert) {
    await visit("/");

    assert
      .dom("[data-test-local-friends-callout-proof]")
      .hasText("People in your area are already here");
  });

  test("topic-list city cards hide privacy-suppressed counts", async function (assert) {
    api.initial = {
      state: "setup",
      current_user: { id: 1, username: "current-user" },
      location: null,
      active_participants: { suppressed: true },
      city_suggestions: [],
      city_directory: {
        active: [
          {
            city: "上海",
            city_key: "上海",
            recent_active_count: null,
            joined_count: null,
            counts_suppressed: true,
          },
        ],
        growing: [],
      },
      settings: {},
    };

    await visit("/");

    assert
      .dom("[data-test-callout-city-card='上海']")
      .includesText("Exact member counts are hidden for privacy")
      .doesNotIncludeText("null");
  });

  test("topic-list city cards open a no-commitment preview without saving inline", async function (assert) {
    api.initial = {
      state: "setup",
      current_user: { id: 1, username: "current-user" },
      location: null,
      active_participants: { suppressed: false, count: 12 },
      city_suggestions: [],
      city_directory: {
        active: [
          {
            city: "上海",
            city_key: "上海",
            recent_active_count: 3,
            joined_count: 5,
          },
        ],
        growing: [],
      },
      settings: {},
    };

    await visit("/");

    assert
      .dom("[data-test-callout-city-card='上海']")
      .hasAttribute(
        "href",
        "/where-is-my-friends?auto_city=%E4%B8%8A%E6%B5%B7"
      );

    await click("[data-test-callout-city-card='上海']");

    assert.strictEqual(api.savedLocations.length, 0);
    assert.true(api.events.includes("local_callout_opened"));
    assert.dom("[data-test-city-input]").hasValue("上海");
  });

  test("the homepage callout records an attributed location save", async function (assert) {
    await visit("/");

    await fillIn("[data-test-callout-city-input]", "上海");
    await click("[data-test-callout-save-city]");

    const saveEvent = api.eventPayloads.find(
      (payload) => payload.get("event_name") === "local_callout_location_saved"
    );
    assert.strictEqual(api.savedLocations.length, 1);
    assert.strictEqual(saveEvent?.get("surface"), "homepage");
  });

  test("returning users can dismiss the topic-list callout with local persistence", async function (assert) {
    api.initial = readyState();

    await visit("/");

    assert.dom("[data-test-local-friends-callout-cta]").hasText("View all");
    await click("[data-test-dismiss-local-friends]");
    assert.dom("[data-test-local-friends-callout]").doesNotExist();
    assert.true(api.events.includes("local_callout_dismissed"));

    await visit("/latest");
    assert.dom("[data-test-local-friends-callout]").doesNotExist();
    assert.notStrictEqual(
      localStorage.getItem(CALLOUT_STORAGE_KEY),
      null,
      "dismissal is persisted"
    );
  });

  test("returning users respect a persisted dismissal cooldown", async function (assert) {
    api.initial = readyState();
    localStorage.setItem(
      CALLOUT_STORAGE_KEY,
      JSON.stringify({
        views: 2,
        cooldownUntil: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
        open: false,
      })
    );

    await visit("/");

    assert.dom("[data-test-local-friends-callout]").doesNotExist();
    assert.strictEqual(api.locationRequests, 0);
  });

  test("topic-list callout is not duplicated on the Local Friends page", async function (assert) {
    await visit("/where-is-my-friends");

    assert.dom("[data-test-local-friends-callout]").doesNotExist();
    assert.dom(".where-is-my-friends").exists();
  });

  test("the target category keeps city discovery after personalization is complete", async function (assert) {
    getOwner(this)
      .lookup("service:current-user")
      .set("where_is_my_friends_interest_onboarding_state", "complete");

    await visit("/c/bug/1");

    assert.dom("[data-test-local-friends-category-callout]").exists();
    assert.dom("[data-test-community-discovery]").doesNotExist();
    const view = api.eventPayloads.find(
      (payload) => payload.get("event_name") === "local_callout_viewed"
    );
    assert.strictEqual(view?.get("surface"), "category");
  });

  test("the target category falls back to the legacy slug when no id is configured", async function (assert) {
    const siteSettings = getOwner(this).lookup("service:site-settings");
    siteSettings.where_is_my_friends_target_category_id = null;
    siteSettings.where_is_my_friends_target_category_slug = "bug";

    await visit("/c/bug/1");

    assert.dom("[data-test-local-friends-category-callout]").exists();
  });

  test("route reuse records an impression for the visible local callout surface", async function (assert) {
    getOwner(this)
      .lookup("service:current-user")
      .set("where_is_my_friends_interest_onboarding_state", "complete");

    await visit("/c/bug/1");
    await visit("/");

    const surfaces = api.eventPayloads
      .filter((payload) => payload.get("event_name") === "local_callout_viewed")
      .map((payload) => payload.get("surface"));
    assert.deepEqual(surfaces, ["category"]);
  });

  test("route reuse does not record a dismissed callout on a new surface", async function (assert) {
    api.initial = readyState();

    await visit("/");
    await click("[data-test-dismiss-local-friends]");
    await visit("/c/bug/1");

    assert.dom("[data-test-local-friends-callout]").doesNotExist();
    const surfaces = api.eventPayloads
      .filter((payload) => payload.get("event_name") === "local_callout_viewed")
      .map((payload) => payload.get("surface"));
    assert.deepEqual(surfaces, ["homepage"]);
  });

  test("the category index keeps city discovery after personalization is complete", async function (assert) {
    getOwner(this)
      .lookup("service:current-user")
      .set("where_is_my_friends_interest_onboarding_state", "complete");

    await visit("/categories");

    assert.dom("[data-test-local-friends-callout]").exists();
    assert.dom("[data-test-community-discovery]").doesNotExist();
  });

  test("setup uses social proof, city suggestions, and an optional region", async function (assert) {
    api.initial = {
      state: "setup",
      current_user: { id: 1, username: "current-user" },
      location: null,
      active_participants: { suppressed: false, count: 12 },
      city_suggestions: [
        { city: "上海", city_key: "上海", count: 2 },
        { city: "北京", city_key: "北京", count: 1 },
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

  test("an unmapped canonical city keeps the category-only compose link", async function (assert) {
    api.initial = {
      state: "setup",
      current_user: { id: 1, username: "current-user" },
      location: null,
      active_participants: { suppressed: true },
      city_suggestions: [],
      city_catalogue: [
        { city: "singapore", city_key: "singapore", region: "Singapore" },
      ],
      city_directory: {
        active: [
          {
            city: "singapore",
            city_key: "singapore",
            recent_active_count: 1,
            joined_count: 1,
          },
        ],
        growing: [],
        cities: [],
      },
      settings: {},
      filterable_fields: [],
    };
    api.preview = {
      city: {
        city: "Singapore",
        city_key: "singapore",
        canonical: true,
        recent_active_count: 0,
        joined_count: 0,
      },
      radius_options: [],
      recommended_radius_km: null,
      nearby_cities: [],
      local_topics: [],
      local_topic_compose_url: "/new-topic?category_id=7",
    };

    await visit("/where-is-my-friends");
    await fillIn("[data-test-city-input]", "Singapore");
    await click("[data-test-preview-city]");

    assert
      .dom("[data-test-city-network-preview] [data-test-compose-local-topic]")
      .hasAttribute("href", "/new-topic?category_id=7");
  });

  test("setup previews the regional network before an explicit join", async function (assert) {
    api.initial = {
      state: "setup",
      current_user: { id: 1, username: "current-user" },
      location: null,
      active_participants: { suppressed: false, count: 12 },
      city_suggestions: [],
      city_catalogue: [
        { city: "上海", city_key: "上海", region: "上海" },
        { city: "苏州", city_key: "苏州", region: "江苏" },
      ],
      city_directory: {
        active: [
          {
            city: "上海",
            city_key: "上海",
            recent_active_count: 1,
            joined_count: 2,
          },
        ],
        growing: [
          {
            city: "苏州",
            city_key: "苏州",
            recent_active_count: 2,
            joined_count: 3,
          },
        ],
        cities: [],
        activity_window_days: 90,
      },
      settings: {
        default_discovery_radius_km: 100,
        discovery_radius_options_km: [50, 100, 200],
      },
      filterable_fields: [],
    };
    api.preview = {
      city: {
        city: "上海",
        city_key: "上海",
        canonical: true,
        recent_active_count: 1,
        joined_count: 2,
      },
      radius_options: [
        {
          radius_km: 50,
          recent_active_count: 1,
          joined_count: 2,
          city_count: 1,
        },
        {
          radius_km: 100,
          recent_active_count: 3,
          joined_count: 5,
          city_count: 2,
        },
        {
          radius_km: 200,
          recent_active_count: 4,
          joined_count: 7,
          city_count: 3,
        },
      ],
      recommended_radius_km: 100,
      nearby_cities: [
        {
          city: "苏州",
          city_key: "苏州",
          approximate_distance_km: 90,
          recent_active_count: 2,
          joined_count: 3,
        },
      ],
      local_topics: [
        {
          id: 41,
          title: "上海周末野餐",
          url: "/t/shanghai-weekend-picnic/41",
          posts_count: 4,
          activity_area: "上海",
        },
      ],
      local_topic_compose_url:
        "/new-topic?category_id=7&tags=%E4%B8%AD%E5%9B%BD,%E4%B8%8A%E6%B5%B7",
    };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-city-directory-active]").exists();
    assert
      .dom("[data-test-city-card='上海']")
      .includesText("1 active")
      .includesText("2 joined");
    assert.dom("[data-test-city-directory-growing]").exists();

    await click("[data-test-city-card='上海']");

    assert.strictEqual(api.previewRequests, 1);
    assert.strictEqual(api.lastPreviewParams.city, "上海");
    assert.strictEqual(api.savedLocations.length, 0);
    assert
      .dom("[data-test-city-network-preview]")
      .includesText("1 active in the last 90 days")
      .includesText("2 joined");
    assert
      .dom("[data-test-preview-radius='100']")
      .hasClass("btn-primary")
      .includesText("3 active");
    assert
      .dom("[data-test-preview-nearby-city='苏州']")
      .includesText("about 90 km")
      .includesText("2 active");
    assert
      .dom("[data-test-city-network-preview] [data-test-local-topic]")
      .doesNotExist();
    assert
      .dom("[data-test-city-network-preview] [data-test-compose-local-topic]")
      .hasAttribute(
        "href",
        "/new-topic?category_id=7&tags=%E4%B8%AD%E5%9B%BD,%E4%B8%8A%E6%B5%B7"
      );
    assert.dom("[data-test-join-notify-city]").isChecked();
    assert.dom("[data-test-join-notify-nearby]").isChecked();
    await click("[data-test-join-notify-nearby]");

    await click("[data-test-join-city]");

    assert.strictEqual(api.savedLocations.length, 1);
    assert.strictEqual(api.savedLocations[0].city, "上海");
    assert.strictEqual(api.savedLocations[0].discovery_radius_km, "100");
    assert.strictEqual(api.savedLocations[0].notify_city, "true");
    assert.strictEqual(api.savedLocations[0].notify_nearby, "false");
  });

  test("setup renders privacy-suppressed city aggregates without exact counts", async function (assert) {
    api.initial = {
      state: "setup",
      current_user: { id: 1, username: "current-user" },
      location: null,
      active_participants: { suppressed: true },
      city_suggestions: [],
      city_catalogue: [{ city: "上海", city_key: "上海", region: "上海" }],
      city_directory: {
        active: [
          {
            city: "上海",
            city_key: "上海",
            recent_active_count: null,
            recent_active_count_suppressed: true,
            joined_count: null,
            joined_count_suppressed: true,
            counts_suppressed: true,
          },
        ],
        growing: [],
        cities: [],
      },
      settings: {},
      filterable_fields: [],
    };
    api.preview = {
      city: {
        city: "上海",
        city_key: "上海",
        canonical: true,
        recent_active_count: null,
        recent_active_count_suppressed: true,
        joined_count: null,
        joined_count_suppressed: true,
        counts_suppressed: true,
      },
      radius_options: [
        {
          radius_km: 50,
          recent_active_count: null,
          recent_active_count_suppressed: true,
          joined_count: null,
          joined_count_suppressed: true,
          counts_suppressed: true,
        },
      ],
      recommended_radius_km: 50,
      nearby_cities: [
        {
          city: "苏州",
          city_key: "苏州",
          approximate_distance_km: 90,
          recent_active_count: null,
          recent_active_count_suppressed: true,
          joined_count: null,
          joined_count_suppressed: true,
          counts_suppressed: true,
        },
      ],
      local_topics: [],
    };

    await visit("/where-is-my-friends");

    assert
      .dom("[data-test-city-card='上海']")
      .includesText("Exact member counts are hidden for privacy")
      .doesNotIncludeText("null");

    await click("[data-test-city-card='上海']");

    assert
      .dom("[data-test-city-network-preview]")
      .includesText("Exact member counts are hidden for privacy");
    assert
      .dom("[data-test-preview-radius='50']")
      .hasText("50 km · exact counts hidden");
    assert
      .dom("[data-test-preview-nearby-city='苏州']")
      .hasText("苏州 about 90 km · exact counts hidden");
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
    api.nearby = {
      state: "empty",
      users: [],
      nearby_city_count: null,
      nearby_city_count_suppressed: true,
    };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-empty-state]").exists();
    assert
      .dom("[data-test-nearby-city-count]")
      .hasText("Members in nearby cities have already joined")
      .doesNotIncludeText("null");
    assert.dom("[data-test-local-topics]").exists();
  });

  test("a bounded visibility scan does not claim there are no results", async function (assert) {
    api.initial = {
      state: "ready",
      current_user: { id: 1, username: "current-user" },
      location: { city: "上海", discovery_mode: "city" },
      active_participants: { suppressed: true },
      city_suggestions: [],
      settings: {},
    };
    api.nearby = {
      state: "limited",
      users: [],
      results_limited: true,
      local_topics: [],
    };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-limited-state]").exists();
    assert.dom("[data-test-empty-state]").doesNotExist();
    assert
      .dom("[data-test-limited-state]")
      .includesText("Some profiles could not be checked")
      .doesNotIncludeText("Be the first connection");
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
      success({
        coords: { latitude: 31.2304, longitude: 121.4737, accuracy: 18 },
      })
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
    assert
      .dom("[data-test-profile-link='alice']")
      .hasAttribute("href", "/u/alice");
    assert
      .dom("[data-test-profile-link='alice']")
      .doesNotHaveClass("btn-primary");
    assert
      .dom("[data-test-profile-link='alice']")
      .hasAttribute("aria-label", "View alice's profile");
    assert
      .dom("[data-test-message-link='alice']")
      .hasAttribute("href", "/chat/new-message?recipients=alice");
    assert
      .dom("[data-test-message-link='alice']")
      .hasAttribute("aria-label", "Send a message to alice")
      .doesNotHaveClass("btn-primary");
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
    assert.true(api.events.includes("local_topic_opened"));
    assert.dom("[data-test-member-filter]").doesNotExist();
  });

  test("expanded regional results report the effective radius", async function (assert) {
    api.initial = readyState();
    api.nearby = {
      state: "ready",
      users: [localUser("alice", "Alice")],
      expanded_radius: true,
      original_radius_km: 100,
      expanded_radius_km: 200,
    };

    await visit("/where-is-my-friends");

    assert
      .dom("[data-test-expanded-radius]")
      .hasText("No members within 100 km — expanded to 200 km");
    assert
      .dom("[data-test-results-summary]")
      .hasText("1 member within 200 km of 上海");
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

    assert
      .dom("[data-test-location-settings-toggle]")
      .hasText("Location settings");
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
    assert.true(api.events.includes("local_topic_opened"));
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

  test("results group members by city and label inactive profiles", async function (assert) {
    api.initial = readyState();
    const activeShanghai = {
      ...localUser("alice", "Alice"),
      activity_status: "recent",
    };
    const inactiveShanghai = {
      ...localUser("bob", "Bob"),
      activity_status: "inactive",
    };
    const activeSuzhou = {
      ...localUser("carol", "Carol"),
      city: "苏州",
      distance_band: "moderate",
      activity_status: "recent",
    };
    api.nearby = {
      state: "ready",
      users: [activeShanghai, inactiveShanghai, activeSuzhou],
      city_groups: [
        {
          city: "上海",
          city_key: "上海",
          distance_band: "same_city",
          approximate_distance_km: null,
          recent_active_count: 1,
          joined_count: 2,
          users: [activeShanghai, inactiveShanghai],
        },
        {
          city: "苏州",
          city_key: "苏州",
          distance_band: "moderate",
          approximate_distance_km: 90,
          recent_active_count: 1,
          joined_count: 1,
          users: [activeSuzhou],
        },
      ],
    };

    await visit("/where-is-my-friends");

    assert
      .dom("[data-test-city-group='上海']")
      .includesText("上海 city")
      .includesText("1 active")
      .includesText("2 joined");
    assert
      .dom("[data-test-city-group='苏州']")
      .includesText("about 90 km")
      .includesText("1 active");
    assert
      .dom("[data-test-user-card='bob'] [data-test-inactive-member]")
      .hasText("Inactive for more than 90 days");
  });

  test("full member cards integrate activity, profile, and attributes without a duplicate spotlight", async function (assert) {
    api.initial = readyState(
      {},
      {
        filterable_fields: [
          { name: "Gender", key: "user_field_3", options: ["Woman"] },
          { name: "Role", key: "user_field_5", options: ["Bottom"] },
        ],
      }
    );
    const onlineMember = {
      ...localUser("alice", "Alice"),
      online: true,
      activity_status: "online",
      last_seen_at: new Date().toISOString(),
      custom_fields: { Gender: "Woman", Role: "Bottom" },
    };
    const activeMember = {
      ...localUser("carol", "Carol"),
      online: false,
      activity_status: "recent",
      last_seen_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
      last_posted_at: new Date(
        Date.now() - 7 * 24 * 60 * 60 * 1000
      ).toISOString(),
    };
    const inactiveMember = {
      ...localUser("bob", "Bob"),
      online: false,
      activity_status: "inactive",
    };
    api.nearby = {
      state: "ready",
      users: [onlineMember, activeMember, inactiveMember],
    };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-reply-now]").doesNotExist();
    assert
      .dom("[data-test-user-card='alice'] [data-test-user-activity]")
      .hasText("Online now");
    assert
      .dom("[data-test-user-card='carol'] [data-test-user-activity]")
      .includesText("Here")
      .includesText("ago");
    assert
      .dom("[data-test-presence-note]")
      .includesText("Online status is approximate");
    assert
      .dom("[data-test-user-card='alice'] [data-test-user-attrs]")
      .hasText("Woman / Bottom");
    assert
      .dom("[data-test-user-card='alice'] [data-test-profile-link='alice']")
      .hasAttribute("href", "/u/alice");
    assert
      .dom("[data-test-user-card='alice'] [data-test-message-link='alice']")
      .hasAttribute("href", "/chat/new-message?recipients=alice");
    assert
      .dom("[data-test-user-card='bob'] [data-test-inactive-member]")
      .exists();
  });

  test("joined results put members before one compact local-topics action", async function (assert) {
    api.initial = readyState();
    api.nearby = {
      state: "ready",
      users: [localUser("alice", "Alice")],
      city_groups: [],
      local_topics: [
        {
          id: 42,
          title: "苏州周六桌游",
          url: "/t/suzhou-board-games/42",
          posts_count: 7,
          activity_area: "江苏",
        },
      ],
      local_topic_compose_url:
        "/new-topic?category_id=7&tags=%E4%B8%AD%E5%9B%BD,%E4%B8%8A%E6%B5%B7",
    };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-local-topic='42']").doesNotExist();
    assert
      .dom("[data-test-local-topics]")
      .hasText("Browse local topics")
      .hasAttribute("href", "/search?q=%E4%B8%8A%E6%B5%B7");
    const topicsAction = document.querySelector("[data-test-local-topics]");
    const directoryOrder = [
      ...document.querySelectorAll(
        "[data-test-user-card], [data-test-local-topics]"
      ),
    ];
    assert.strictEqual(
      directoryOrder[directoryOrder.length - 1],
      topicsAction,
      "the member directory appears before the topics action"
    );
    assert
      .dom("[data-test-message-link='alice']")
      .doesNotHaveClass("btn-primary");
  });

  test("attribute filters render from filterable_fields and send params on selection", async function (assert) {
    api.initial = readyState(
      {},
      {
        filterable_fields: [
          { name: "性别", key: "user_field_3", options: ["男", "女", "其他"] },
          {
            name: "属性",
            key: "user_field_5",
            options: ["主动", "被动", "双"],
          },
        ],
      }
    );
    api.nearby = {
      state: "ready",
      users: [
        {
          ...localUser("alice", "Alice"),
          custom_fields: { 性别: "女", 属性: "被动" },
        },
        {
          ...localUser("bob", "Bob"),
          custom_fields: { 性别: "男", 属性: "主动" },
        },
      ],
    };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-attribute-filters]").exists();
    assert.dom("[data-test-filter-group='user_field_3']").exists();
    assert.dom("[data-test-filter-group='user_field_5']").exists();

    assert
      .dom(
        "[data-test-filter-group='user_field_3'] [data-test-filter-option='all']"
      )
      .hasClass("btn-primary");

    await click(
      "[data-test-filter-group='user_field_3'] [data-test-filter-option='男']"
    );

    assert.strictEqual(api.nearbyRequests, 2);
    assert.strictEqual(api.lastNearbyParams["filters[user_field_3]"], "男");

    assert
      .dom(
        "[data-test-filter-group='user_field_3'] [data-test-filter-option='男']"
      )
      .hasClass("btn-primary");
    assert
      .dom(
        "[data-test-filter-group='user_field_3'] [data-test-filter-option='all']"
      )
      .doesNotHaveClass("btn-primary");
  });

  test("clicking 'All' clears the filter for that field", async function (assert) {
    api.initial = readyState(
      {},
      {
        filterable_fields: [
          { name: "性别", key: "user_field_3", options: ["男", "女"] },
        ],
      }
    );
    api.nearby = {
      state: "ready",
      users: [localUser("alice", "Alice")],
    };

    await visit("/where-is-my-friends");

    await click(
      "[data-test-filter-group='user_field_3'] [data-test-filter-option='男']"
    );
    assert.strictEqual(api.lastNearbyParams["filters[user_field_3]"], "男");

    await click(
      "[data-test-filter-group='user_field_3'] [data-test-filter-option='all']"
    );
    assert.strictEqual(api.nearbyRequests, 3);
    assert.strictEqual(
      api.lastNearbyParams["filters[user_field_3]"],
      undefined
    );
  });

  test("custom field values are shown on user cards", async function (assert) {
    api.initial = readyState(
      {},
      {
        filterable_fields: [
          { name: "性别", key: "user_field_3", options: ["男", "女"] },
          {
            name: "属性",
            key: "user_field_5",
            options: ["主动", "被动", "双"],
          },
        ],
      }
    );
    api.nearby = {
      state: "ready",
      users: [
        {
          ...localUser("alice", "Alice"),
          custom_fields: { 性别: "女", 属性: "被动" },
        },
      ],
    };

    await visit("/where-is-my-friends");

    assert
      .dom("[data-test-user-card='alice'] [data-test-user-attrs]")
      .hasText("女 / 被动");
  });

  test("filter UI is hidden when no filterable fields are configured", async function (assert) {
    api.initial = readyState();
    api.nearby = {
      state: "ready",
      users: [localUser("alice", "Alice")],
    };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-attribute-filters]").doesNotExist();
  });

  test("discovery radius can be changed and reloads nearby results", async function (assert) {
    api.initial = readyState();
    api.nearby = { state: "ready", users: [localUser("alice", "Alice")] };

    await visit("/where-is-my-friends");

    assert.dom("[data-test-discovery-radius]").exists();
    assert
      .dom("[data-test-discovery-radius-option='100']")
      .hasClass("btn-primary");

    await click("[data-test-discovery-radius-option='200']");

    assert.strictEqual(api.savedLocations.length, 1);
    assert.strictEqual(api.savedLocations[0].discovery_radius_km, "200");
    assert.strictEqual(api.nearbyRequests, 2);
    assert
      .dom("[data-test-results-summary]")
      .hasText("1 member within 200 km of 上海");
  });
});

function readyState(settings = {}, extras = {}) {
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
    filterable_fields: [],
    ...extras,
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
