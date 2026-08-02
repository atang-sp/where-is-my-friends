import { getOwner } from "@ember/owner";
import {
  click,
  fillIn,
  find,
  settled,
  visit,
  waitFor,
} from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

function pendingModel() {
  return {
    state: "pending",
    catalogue: [
      {
        id: 1,
        name: "ruby",
        group_key: "content_interest",
        group_name: "Content interests",
      },
      {
        id: 2,
        name: "design",
        group_key: "content_interest",
        group_name: "Content interests",
      },
      {
        id: 3,
        name: "community",
        group_key: "communication_style",
        group_name: "Communication",
      },
      {
        id: 4,
        name: "writing",
        group_key: "content_interest",
        group_name: "Content interests",
      },
    ],
    catalogue_groups: [
      {
        key: "content_interest",
        name: "Content interests",
        description: "What you want to read and discuss.",
        selection_mode: "multi",
        max_per_group: 3,
      },
      {
        key: "communication_style",
        name: "Communication",
        description: "How you want to participate.",
        selection_mode: "multi",
        max_per_group: 3,
      },
    ],
    selection_limits: { minimum: 3, maximum: 20 },
    purposes: ["learn", "share", "connect", "ask", "help", "browse"],
    profile: {
      purpose: null,
      personalization_enabled: true,
      recommendable: true,
      show_interests_publicly: false,
      interests: [],
    },
    recommended_topics: [],
    recommended_users: [],
  };
}

function completedModel() {
  return {
    ...pendingModel(),
    state: "complete",
    profile: {
      purpose: "learn",
      personalization_enabled: true,
      recommendable: true,
      show_interests_publicly: false,
      interests: [
        { id: 1, name: "ruby" },
        { id: 2, name: "design" },
        { id: 3, name: "community" },
      ],
    },
    recommended_topics: [
      {
        id: 101,
        title: "Practical Ruby",
        fancy_title: "Practical Ruby",
        url: "/t/practical-ruby/101",
        matching_interests: [{ id: 1, name: "ruby" }],
        participation_state: "awaiting_response",
        candidate_source: "interest",
        rank: 1,
        rank_bucket: "one_to_two",
      },
    ],
    recommended_users: [
      {
        id: 9,
        username: "alice",
        name: "Alice",
        profile_url: "/u/alice",
        bio_excerpt: "Writes practical guides.",
        reason_interests: [{ id: 1, name: "ruby" }],
        invitation_interests: [{ id: 1, name: "ruby" }],
        representative_topics: [
          {
            id: 101,
            title: "Practical Ruby",
            url: "/t/practical-ruby/101",
          },
        ],
        candidate_source: "interest",
        rank: 1,
        rank_bucket: "one_to_two",
        invite_url: "/where-is-my-friends/interests?invite_to=alice",
      },
    ],
    recommended_interests: [
      {
        id: 1,
        name: "ruby",
        url: "/tag/ruby/1",
        candidate_source: "interest",
        topic_count: 12,
        new_topic_count: 3,
        active_member_count: null,
        active_member_count_suppressed: true,
        rank: 1,
        rank_bucket: "one_to_two",
      },
    ],
    algorithm_version: "participation_v1",
  };
}

function homepageModel() {
  const model = completedModel();
  return {
    ...model,
    recommended_topics: Array.from({ length: 4 }, (_, index) => ({
      ...model.recommended_topics[0],
      id: 101 + index,
      title: `Practical Ruby ${index + 1}`,
      fancy_title: `Practical Ruby ${index + 1}`,
      url: `/t/practical-ruby-${index + 1}/${101 + index}`,
      rank: index + 1,
      rank_bucket: index < 2 ? "one_to_two" : "three_to_five",
    })),
    recommended_users: Array.from({ length: 4 }, (_, index) => ({
      ...model.recommended_users[0],
      id: 9 + index,
      username: `member${index + 1}`,
      name: `Member ${index + 1}`,
      profile_url: `/u/member${index + 1}`,
      invite_url: `/where-is-my-friends/interests?invite_to=member${index + 1}`,
      rank: index + 1,
      rank_bucket: index < 2 ? "one_to_two" : "three_to_five",
    })),
    recommended_interests: Array.from({ length: 3 }, (_, index) => ({
      ...model.recommended_interests[0],
      id: index + 1,
      name: ["ruby", "design", "community"][index],
      url: `/tag/${["ruby", "design", "community"][index]}/${index + 1}`,
      candidate_source: index === 1 ? "exploration" : "interest",
      reason_interest: index === 1 ? { id: 1, name: "ruby" } : null,
      rank: index + 1,
      rank_bucket: index < 2 ? "one_to_two" : "three_to_five",
    })),
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

function setupApi(needs, state) {
  needs.pretender((server, helper) => {
    server.get("/where-is-my-friends.json", () => {
      state.locationRequests += 1;
      return helper.response({
        state: "setup",
        current_user: { id: 1, username: "current-user" },
        location: null,
        active_participants: { suppressed: true },
        city_suggestions: [],
        settings: {},
        filterable_fields: [],
      });
    });

    server.get("/where-is-my-friends/recommendations.json", (request) =>
      {
        state.recommendationRequests += 1;
        state.lastRefresh = request.queryParams.refresh ?? null;
        if (state.recommendationError) {
          return helper.response(500, { errors: ["unavailable"] });
        }
        if (state.deferRecommendations) {
          return new Promise((resolve) => {
            state.resolveRecommendations = () =>
              resolve(helper.response(state.model));
          });
        }
        return helper.response(state.model);
      }
    );

    server.get("/where-is-my-friends/practice-invitations.json", () =>
      helper.response({
        incoming: state.incoming,
        outgoing: state.outgoing,
        accepting_invitations: true,
      })
    );

    server.get(
      "/where-is-my-friends/practice-invitations/availability.json",
      (request) => {
        state.availabilityRequests += 1;
        state.availabilityUsername = request.queryParams.username;
        return helper.response({
          available: true,
          recipient_id: 9,
          username: "alice",
          name: "Alice",
          interests: [{ id: 1, name: "ruby" }],
        });
      }
    );

    server.get(
      "/where-is-my-friends/legacy-practice-bookmarks.json",
      () => helper.response({ bookmarks: state.legacyBookmarks })
    );

    server.put(
      "/where-is-my-friends/legacy-practice-bookmarks/:id/reconfirm.json",
      () => {
        state.reconfirmRequests += 1;
        const bookmark = {
          ...state.legacyBookmarks[0],
          state: "reconfirmed",
        };
        state.legacyBookmarks = [bookmark];
        return helper.response({ bookmark });
      }
    );

    server.put(
      "/where-is-my-friends/legacy-practice-bookmarks/:id/dismiss.json",
      () => helper.response({ bookmark: { state: "dismissed" } })
    );

    server.post(
      "/where-is-my-friends/practice-invitations.json",
      (request) => {
        state.invitationParams = new URLSearchParams(request.requestBody);
        const invitation = {
          id: 77,
          status: "pending",
          sender: { id: 1, username: "current-user" },
          recipient: { id: 9, username: "alice", name: "Alice" },
          interest: { id: 1, name: "ruby" },
          note: state.invitationParams.get("note"),
          preset_message: "Invite @alice to practice ruby.",
        };
        state.outgoing = [invitation];
        return helper.response({ invitation });
      }
    );

    server.put(
      "/where-is-my-friends/practice-invitations/:id/accept.json",
      () => {
        state.acceptRequests += 1;
        const invitation = {
          ...state.incoming[0],
          status: "accepted",
          pm_topic_id: 555,
          pm_url: "/t/555",
        };
        state.incoming = [invitation];
        return helper.response({ invitation });
      }
    );

    server.put(
      "/where-is-my-friends/practice-invitations/:id/decline.json",
      () => helper.response({ invitation: { status: "declined" } })
    );

    server.put(
      "/where-is-my-friends/practice-invitations/:id/ignore.json",
      () => helper.response({ invitation: { status: "ignored" } })
    );

    server.put(
      "/where-is-my-friends/recommendations/profile.json",
      (request) => {
        if (state.saveError) {
          return helper.response(422, { errors: [state.saveError] });
        }
        state.savedParams = new URLSearchParams(request.requestBody);
        state.model = completedModel();
        return helper.response(state.model);
      }
    );

    server.post(
      "/where-is-my-friends/recommendations/skip.json",
      () => {
        state.skipRequests += 1;
        return helper.response({ state: "dismissed" });
      }
    );

    server.post(
      "/where-is-my-friends/recommendations/dismiss.json",
      (request) => {
        state.dismissedParams = new URLSearchParams(request.requestBody);
        state.model = {
          ...completedModel(),
          recommended_topics: [],
        };
        return helper.response(state.model);
      }
    );

    server.delete(
      "/where-is-my-friends/recommendations/profile.json",
      () => {
        state.disableRequests += 1;
        return helper.response({ state: "dismissed" });
      }
    );

    server.post("/where-is-my-friends/events.json", (request) => {
      state.events.push(
        new URLSearchParams(request.requestBody).get("event_name")
      );
      state.eventPayloads.push(new URLSearchParams(request.requestBody));
      return helper.response({ success: "OK" });
    });
  });
}

acceptance("Where Is My Friends | interest onboarding", function (needs) {
  needs.settings({
    where_is_my_friends_enabled: true,
    where_is_my_friends_interest_onboarding_enabled: true,
    where_is_my_friends_practice_invitations_enabled: true,
  });
  needs.user({
    username: "current-user",
    where_is_my_friends_interest_onboarding_state: "pending",
  });

  const api = {};

  needs.hooks.beforeEach(() => {
    Object.assign(api, {
      model: pendingModel(),
      savedParams: null,
      dismissedParams: null,
      skipRequests: 0,
      disableRequests: 0,
      saveError: null,
      events: [],
      eventPayloads: [],
      recommendationRequests: 0,
      locationRequests: 0,
      recommendationError: false,
      deferRecommendations: false,
      resolveRecommendations: null,
      lastRefresh: null,
      incoming: [],
      outgoing: [],
      invitationParams: null,
      acceptRequests: 0,
      availabilityRequests: 0,
      availabilityUsername: null,
      legacyBookmarks: [],
      reconfirmRequests: 0,
    });
  });

  setupApi(needs, api);

  test("a pending member sees the one-time topic-list prompt", async function (assert) {
    await visit("/");

    assert.dom("[data-test-interest-onboarding-callout]").exists();
    assert
      .dom("[data-test-open-interest-onboarding]")
      .hasAttribute("href", "/where-is-my-friends/interests");
    assert.dom("[data-test-local-friends-callout]").doesNotExist();
    assert.strictEqual(api.locationRequests, 0);
    assert.true(api.events.includes("interest_prompt_viewed"));

    await click("[data-test-skip-interest-callout]");

    assert.strictEqual(api.skipRequests, 1);
    assert.dom("[data-test-interest-onboarding-callout]").doesNotExist();
    assert.dom("[data-test-local-friends-callout]").exists();
    assert.strictEqual(api.locationRequests, 1);
  });

  test("a completed member sees local friends and collapsed community discovery without loading recommendations", async function (assert) {
    api.model = homepageModel();
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");

    assert.dom("[data-test-community-discovery]").exists();
    assert.dom("[data-test-local-friends-callout]").exists();
    assert.strictEqual(api.locationRequests, 1);
    assert
      .dom("[data-test-community-toggle]")
      .hasAttribute("aria-expanded", "false")
      .hasText("Expand");
    assert.dom("[data-test-community-content]").doesNotExist();
    assert.dom("[data-test-community-topic]").doesNotExist();
    assert.dom("[data-test-community-person]").doesNotExist();
    assert.dom("[data-test-community-interest]").doesNotExist();
    assert.strictEqual(api.recommendationRequests, 0);
    assert.false(api.events.includes("recommendation_impression"));
  });

  test("first expansion loads and exposes only the discussion group", async function (assert) {
    api.model = homepageModel();
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");
    await click("[data-test-community-toggle]");

    assert
      .dom("[data-test-community-toggle]")
      .hasAttribute("aria-expanded", "true")
      .hasText("Collapse");
    assert.strictEqual(api.recommendationRequests, 1);
    assert.dom("[data-test-community-content]").exists();
    assert
      .dom("[data-test-community-group='topics']")
      .hasAttribute("aria-pressed", "true")
      .hasText("Discussions 3");
    assert
      .dom("[data-test-community-group='people']")
      .hasAttribute("aria-pressed", "false")
      .hasText("Members 3");
    assert
      .dom("[data-test-community-group='interests']")
      .hasAttribute("aria-pressed", "false")
      .hasText("Interests 2");
    assert.dom("[data-test-community-topic]").exists({ count: 3 });
    assert.dom("[data-test-community-person]").doesNotExist();
    assert.dom("[data-test-community-interest]").doesNotExist();

    const impressions = api.eventPayloads.filter(
      (payload) => payload.get("event_name") === "recommendation_impression"
    );
    const expansion = api.eventPayloads.find(
      (payload) =>
        payload.get("event_name") === "recommendation_panel_expanded"
    );
    assert.strictEqual(expansion?.get("surface"), "homepage");
    assert.strictEqual(expansion?.get("recommendation_group"), "topics");
    assert.strictEqual(impressions.length, 3);
    assert.true(
      impressions.every(
        (payload) =>
          payload.get("surface") === "homepage" &&
          payload.get("recommendation_group") === "topics" &&
          payload.get("algorithm_version") === "participation_v1" &&
          payload.get("result_count") === "8" &&
          payload.get("target_id") === null &&
          payload.get("topic_id") === null
      ),
      "only visible cards produce coarse impressions"
    );
  });

  test("group switches render and expose only the selected recommendations", async function (assert) {
    api.model = homepageModel();
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");
    await click("[data-test-community-toggle]");
    await click("[data-test-community-group='people']");

    assert
      .dom("[data-test-community-group='people']")
      .hasAttribute("aria-pressed", "true");
    assert.dom("[data-test-community-topic]").doesNotExist();
    assert.dom("[data-test-community-person]").exists({ count: 3 });
    assert.dom("[data-test-community-interest]").doesNotExist();
    assert.strictEqual(api.recommendationRequests, 1);
    assert.strictEqual(
      api.events.filter((event) => event === "recommendation_impression").length,
      6
    );

    await click("[data-test-community-group='interests']");

    assert
      .dom("[data-test-community-group='interests']")
      .hasAttribute("aria-pressed", "true");
    assert.dom("[data-test-community-topic]").doesNotExist();
    assert.dom("[data-test-community-person]").doesNotExist();
    assert.dom("[data-test-community-interest]").exists({ count: 2 });
    assert.strictEqual(api.recommendationRequests, 1);
    assert.strictEqual(
      api.events.filter((event) => event === "recommendation_impression").length,
      8
    );
    assert.deepEqual(
      api.eventPayloads
        .filter(
          (payload) =>
            payload.get("event_name") === "recommendation_group_selected"
        )
        .map((payload) => payload.get("recommendation_group")),
      ["people", "interests"]
    );
    assert.deepEqual(
      api.eventPayloads
        .filter(
          (payload) => payload.get("event_name") === "recommendation_impression"
        )
        .reduce((counts, payload) => {
          const group = payload.get("recommendation_group");
          counts[group] = (counts[group] ?? 0) + 1;
          return counts;
        }, {}),
      { topics: 3, people: 3, interests: 2 }
    );
  });

  test("collapse and reopen retain the selected loaded group", async function (assert) {
    api.model = homepageModel();
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");
    await click("[data-test-community-toggle]");
    await click("[data-test-community-group='people']");
    await click("[data-test-community-toggle]");

    assert.dom("[data-test-community-content]").doesNotExist();
    assert.strictEqual(api.recommendationRequests, 1);

    await click("[data-test-community-toggle]");

    assert.dom("[data-test-community-person]").exists({ count: 3 });
    assert
      .dom("[data-test-community-group='people']")
      .hasAttribute("aria-pressed", "true");
    assert.strictEqual(api.recommendationRequests, 1);
    assert.strictEqual(
      api.events.filter((event) => event === "recommendation_impression").length,
      9,
      "reopening records the three cards that became visible again"
    );
    assert.strictEqual(
      api.events.filter(
        (event) => event === "recommendation_panel_expanded"
      ).length,
      2
    );
    assert.strictEqual(
      api.events.filter(
        (event) => event === "recommendation_panel_collapsed"
      ).length,
      1
    );
    const collapsed = api.eventPayloads.find(
      (payload) =>
        payload.get("event_name") === "recommendation_panel_collapsed"
    );
    assert.strictEqual(collapsed?.get("recommendation_group"), "people");
  });

  test("re-entering the homepage starts collapsed again", async function (assert) {
    api.model = homepageModel();
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");
    await click("[data-test-community-toggle]");
    assert.dom("[data-test-community-content]").exists();

    await visit("/where-is-my-friends");
    await visit("/");

    assert
      .dom("[data-test-community-toggle]")
      .hasAttribute("aria-expanded", "false");
    assert.dom("[data-test-community-content]").doesNotExist();
    assert.strictEqual(
      api.recommendationRequests,
      1,
      "the new homepage entry does not reuse or reload the previous component"
    );
  });

  test("refresh reloads and re-exposes only the active group", async function (assert) {
    api.model = homepageModel();
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");
    await click("[data-test-community-toggle]");
    await click("[data-test-community-refresh]");

    assert.strictEqual(api.recommendationRequests, 2);
    assert.strictEqual(api.lastRefresh, "1");
    assert.dom("[data-test-community-topic]").exists({ count: 3 });
    assert.dom("[data-test-community-person]").doesNotExist();
    assert.strictEqual(
      api.events.filter((event) => event === "recommendation_impression").length,
      6
    );
    const refresh = api.eventPayloads.find(
      (payload) => payload.get("event_name") === "recommendation_refreshed"
    );
    assert.strictEqual(refresh?.get("surface"), "homepage");
    assert.strictEqual(refresh?.get("recommendation_group"), "topics");
  });

  test("member cards prioritize a related discussion and keep secondary actions", async function (assert) {
    api.model = homepageModel();
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");
    await click("[data-test-community-toggle]");
    await click("[data-test-community-group='people']");

    assert
      .dom("[data-test-community-person-primary-action]")
      .exists({ count: 3 });
    assert
      .dom("[data-test-community-person='member1'] .btn-primary")
      .exists({ count: 1 });
    assert
      .dom("[data-test-community-person-primary-action]")
      .hasAttribute("href", "/t/practical-ruby/101");
    assert
      .dom("[data-test-community-person-profile-action]")
      .hasClass("btn-flat");
    assert
      .dom("[data-test-community-person-invite-action]")
      .hasClass("btn-flat");

    await triggerTrackedLink(
      "[data-test-community-person-primary-action]"
    );
    await triggerTrackedLink("[data-test-community-person-profile-action]");
    await triggerTrackedLink("[data-test-community-person-invite-action]");

    assert.true(
      api.events.includes("recommended_user_related_topic_opened")
    );
    assert.true(api.events.includes("recommended_user_profile_opened"));
    assert.true(api.events.includes("recommended_user_invite_started"));
  });

  test("not interested updates only the visible group and shows its empty state", async function (assert) {
    api.model = homepageModel();
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");
    await click("[data-test-community-toggle]");
    await click("[data-test-community-dismiss]");

    assert.strictEqual(api.dismissedParams.get("target_type"), "topic");
    assert.strictEqual(api.dismissedParams.get("target_id"), "101");
    assert.strictEqual(api.dismissedParams.get("surface"), "homepage");
    assert.dom("[data-test-community-topic]").doesNotExist();
    assert.dom("[data-test-community-empty]").exists();
    assert
      .dom("[data-test-community-group='topics']")
      .hasText("Discussions 0");
    assert
      .dom("[data-test-community-group='people']")
      .hasText("Members 1");
    assert.dom("[data-test-community-person]").doesNotExist();
  });

  test("recommendation errors stay inside the expanded panel and can be retried", async function (assert) {
    api.model = homepageModel();
    api.recommendationError = true;
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");
    await click("[data-test-community-toggle]");

    assert.dom("[data-test-community-content]").exists();
    assert.dom("[data-test-community-error]").exists();
    assert.dom("[data-test-community-topic]").doesNotExist();
    assert.false(api.events.includes("recommendation_impression"));

    api.recommendationError = false;
    await click("[data-test-community-retry]");

    assert.strictEqual(api.recommendationRequests, 2);
    assert.dom("[data-test-community-error]").doesNotExist();
    assert.dom("[data-test-community-topic]").exists({ count: 3 });
  });

  test("an empty recommendation response stays inside the expanded panel", async function (assert) {
    api.model = {
      ...homepageModel(),
      recommended_topics: [],
      recommended_users: [],
      recommended_interests: [],
    };
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");
    await click("[data-test-community-toggle]");

    assert.dom("[data-test-community-content]").exists();
    assert.dom("[data-test-community-empty]").exists();
    assert
      .dom("[data-test-community-group='topics']")
      .hasText("Discussions 0");
    assert
      .dom("[data-test-community-group='people']")
      .hasText("Members 0");
    assert
      .dom("[data-test-community-group='interests']")
      .hasText("Interests 0");
    assert.false(api.events.includes("recommendation_impression"));
  });

  test("the expanded panel shows a compact skeleton while recommendations load", async function (assert) {
    api.model = homepageModel();
    api.deferRecommendations = true;
    getOwner(this).lookup("service:current-user").set(
      "where_is_my_friends_interest_onboarding_state",
      "complete"
    );

    await visit("/");
    const expansion = click("[data-test-community-toggle]");
    await waitFor("[data-test-community-skeleton]");

    assert.dom("[data-test-community-content]").exists();
    assert.dom("[data-test-community-skeleton]").exists({ count: 3 });
    assert.dom("[data-test-community-topic]").doesNotExist();
    assert.false(api.events.includes("recommendation_impression"));

    api.deferRecommendations = false;
    api.resolveRecommendations();
    await expansion;

    assert.dom("[data-test-community-skeleton]").doesNotExist();
    assert.dom("[data-test-community-topic]").exists({ count: 3 });
  });

  test("private-by-default choices immediately produce explainable recommendations", async function (assert) {
    await visit("/where-is-my-friends/interests");

    assert.dom("[data-test-interest-onboarding-form]").exists();
    assert.dom("[data-test-recommendable]").isChecked();
    assert.dom("[data-test-public-interests]").isNotChecked();
    assert.dom("[data-test-save-interests]").isDisabled();

    await click("[data-test-interest='ruby']");
    await click("[data-test-interest='design']");
    await click("[data-test-interest='community']");
    await click("[data-test-purpose='learn']");
    await click("[data-test-save-interests]");

    assert.deepEqual(
      api.savedParams.getAll("interest_ids[]"),
      ["1", "2", "3"]
    );
    assert.strictEqual(api.savedParams.get("purpose"), "learn");
    assert.strictEqual(
      api.savedParams.get("show_interests_publicly"),
      "false"
    );
    assert.dom("[data-test-recommended-topic='101']").exists();
    assert.dom("[data-test-recommended-user='alice']").exists();
    assert.dom("[data-test-recommended-topic='101']").includesText("ruby");

    await visit("/");
    assert
      .dom("[data-test-community-discovery]")
      .exists("the completed state activates discovery without a page reload");
  });

  test("the rich catalogue is grouped and searchable", async function (assert) {
    await visit("/where-is-my-friends/interests");

    assert
      .dom("[data-test-interest-group='content_interest']")
      .includesText("Content interests");
    assert
      .dom("[data-test-interest-group='communication_style']")
      .includesText("Communication");

    await fillIn("[data-test-interest-search]", "design");

    assert.dom("[data-test-interest='design']").exists();
    assert.dom("[data-test-interest='ruby']").doesNotExist();
    assert
      .dom("[data-test-interest-group='communication_style']")
      .doesNotExist();
  });

  test("members can dismiss, edit, and fully clear personalization", async function (assert) {
    api.model = completedModel();

    await visit("/where-is-my-friends/interests");

    const impressions = api.eventPayloads.filter(
      (payload) => payload.get("event_name") === "recommendation_impression"
    );
    assert.strictEqual(impressions.length, 2);
    assert.deepEqual(
      impressions.map((payload) => payload.get("recommendation_group")),
      ["topics", "people"]
    );
    assert.true(
      impressions.every(
        (payload) =>
          payload.get("surface") === "interest_page" &&
          payload.get("algorithm_version") === "participation_v1" &&
          payload.get("result_count") === "2" &&
          payload.get("target_id") === null
      )
    );

    await click("[data-test-dismiss-topic='101']");

    assert.strictEqual(api.dismissedParams.get("target_type"), "topic");
    assert.strictEqual(api.dismissedParams.get("target_id"), "101");
    assert.strictEqual(api.dismissedParams.get("surface"), "interest_page");
    assert.strictEqual(api.dismissedParams.get("candidate_source"), "interest");
    assert.strictEqual(api.dismissedParams.get("rank"), "1");
    assert.dom("[data-test-recommended-topic='101']").doesNotExist();

    await click("[data-test-edit-interests]");
    assert.dom("[data-test-interest-onboarding-form]").exists();

    await click("[data-test-save-interests]");
    await click("summary");
    await click("[data-test-disable-personalization]");

    assert.strictEqual(api.disableRequests, 1);
    assert.dom("[data-test-interest-dismissed]").exists();
  });

  test("a recommended member can receive a one-to-one practice invitation", async function (assert) {
    api.model = completedModel();

    await visit("/where-is-my-friends/interests");
    await click("[data-test-invite-user='9']");

    assert.dom("[data-test-practice-invitation-form]").exists();
    assert
      .dom("[data-test-practice-invitation-preview]")
      .includesText("alice")
      .includesText("ruby");

    await fillIn(
      "[data-test-practice-invitation-note]",
      "Bring one small kata."
    );
    await fillIn(
      "[data-test-practice-invitation-time]",
      "2026-07-30T10:00"
    );
    await click("[data-test-send-practice-invitation]");

    assert.strictEqual(api.invitationParams.get("recipient_id"), "9");
    assert.strictEqual(api.invitationParams.get("tag_id"), "1");
    assert.strictEqual(
      api.invitationParams.get("note"),
      "Bring one small kata."
    );
    assert.strictEqual(
      api.invitationParams.get("proposed_at"),
      new Date("2026-07-30T10:00").toISOString()
    );
    assert.dom("[data-test-practice-invitation-form]").doesNotExist();
    assert.dom("[data-test-outgoing-invitation='77']").includesText("alice");
  });

  test("a profile invitation link opens the invitation form", async function (assert) {
    api.model = completedModel();

    await visit("/where-is-my-friends/interests?invite_to=alice");

    assert.strictEqual(api.availabilityRequests, 1);
    assert.strictEqual(api.availabilityUsername, "alice");
    assert.dom("[data-test-practice-invitation-form]").exists();
    assert
      .dom("[data-test-practice-invitation-preview]")
      .includesText("alice")
      .includesText("ruby");
  });

  test("an incoming invitation can be accepted into its one-to-one PM", async function (assert) {
    api.model = completedModel();
    api.incoming = [
      {
        id: 88,
        status: "pending",
        sender: { id: 9, username: "alice", name: "Alice" },
        recipient: { id: 1, username: "current-user" },
        interest: { id: 1, name: "ruby" },
        proposed_at: "2026-07-30T10:00:00.000Z",
        note: "Bring one small kata.",
        preset_message: "Invite @current-user to practice ruby.",
      },
    ];

    await visit("/where-is-my-friends/interests");

    assert.dom("[data-test-incoming-invitation='88']").includesText("alice");
    await click("[data-test-accept-practice-invitation='88']");

    assert.strictEqual(api.acceptRequests, 1);
    assert
      .dom("[data-test-incoming-invitation='88'] a")
      .hasAttribute("href", "/t/555");
  });

  test("a migrated legacy intent requires explicit reconfirmation and never auto-sends", async function (assert) {
    api.model = completedModel();
    api.legacyBookmarks = [
      {
        id: 99,
        state: "needs_reconfirmation",
        target: { id: 9, username: "alice", name: "Alice" },
        source_created_at: "2026-07-01T10:00:00.000Z",
        mutual_history: true,
      },
    ];

    await visit("/where-is-my-friends/interests");

    assert
      .dom("[data-test-legacy-practice-bookmark='99']")
      .includesText("alice");
    assert.strictEqual(api.invitationParams, null);

    await click("[data-test-reconfirm-legacy-practice='99']");

    assert.strictEqual(api.reconfirmRequests, 1);
    assert.strictEqual(api.invitationParams, null);
    assert
      .dom("[data-test-legacy-practice-bookmark='99']")
      .includesText("Reconfirmed");
  });

  test("an empty catalogue has a safe, skippable state", async function (assert) {
    api.model = { ...pendingModel(), catalogue: [] };

    await visit("/where-is-my-friends/interests");

    assert.dom("[data-test-interest-catalogue-empty]").exists();
    await click("[data-test-skip-interests]");
    assert.strictEqual(api.skipRequests, 1);
    assert.dom("[data-test-interest-dismissed]").exists();
  });

  test("editing drops interests that are no longer in the visible catalogue", async function (assert) {
    api.model = {
      ...completedModel(),
      profile: {
        ...completedModel().profile,
        interests: [
          ...completedModel().profile.interests,
          { id: 99, name: "retired-interest" },
        ],
      },
    };

    await visit("/where-is-my-friends/interests");
    await click("[data-test-edit-interests]");
    await click("[data-test-save-interests]");

    assert.deepEqual(
      api.savedParams.getAll("interest_ids[]"),
      ["1", "2", "3"]
    );
  });

  test("a failed save shows the server error and leaves the form editable", async function (assert) {
    api.saveError = "Could not save these interests.";

    await visit("/where-is-my-friends/interests");
    await click("[data-test-interest='ruby']");
    await click("[data-test-interest='design']");
    await click("[data-test-interest='community']");
    await click("[data-test-purpose='learn']");
    await click("[data-test-save-interests]");

    assert
      .dom("[data-test-interest-error]")
      .hasText("Could not save these interests.");
    assert.dom("[data-test-interest-onboarding-form]").exists();
    assert.dom("[data-test-save-interests]").isEnabled();
  });
});

acceptance(
  "Where Is My Friends | disabled homepage personalization",
  function (needs) {
    needs.settings({
      where_is_my_friends_enabled: true,
      where_is_my_friends_interest_onboarding_enabled: false,
    });
    needs.user({
      username: "current-user",
      where_is_my_friends_interest_onboarding_state: "complete",
    });

    let locationRequests = 0;
    needs.pretender((server, helper) => {
      server.get("/where-is-my-friends.json", () => {
        locationRequests += 1;
        return helper.response({
          state: "setup",
          current_user: { id: 1, username: "current-user" },
          location: null,
          active_participants: { suppressed: true },
          city_suggestions: [],
          settings: {},
          filterable_fields: [],
        });
      });
      server.post("/where-is-my-friends/events.json", () =>
        helper.response({ success: "OK" })
      );
    });

    test("the existing city entry remains when personalization is disabled", async function (assert) {
      await visit("/");

      assert.dom("[data-test-community-discovery]").doesNotExist();
      assert.dom("[data-test-interest-onboarding-callout]").doesNotExist();
      assert.dom("[data-test-local-friends-callout]").exists();
      assert.strictEqual(locationRequests, 1);
    });
  }
);
