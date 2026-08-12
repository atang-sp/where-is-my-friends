import { click, fillIn, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

function locationResponse() {
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
    settings: {},
    filterable_fields: [],
  };
}

function nearbyResponse() {
  return {
    state: "ready",
    users: [
      {
        id: 2,
        username: "friend",
        name: "Friend",
        avatar_template: "/letter_avatar_proxy/v4/letter/f/1.png",
        city: "上海",
        user_tags: [
          {
            id: 11,
            label: "热心肠",
            endorser_count: 3,
            endorsed_by_me: false,
          },
        ],
      },
    ],
    city_groups: [],
    local_topics: [],
    local_topic_compose_url: "/new-topic?category=1",
  };
}

acceptance("Where Is My Friends | impression tags", function (needs) {
  needs.settings({
    where_is_my_friends_enabled: true,
    where_is_my_friends_first_connection_enabled: false,
    where_is_my_friends_user_tags_enabled: true,
    where_is_my_friends_user_tag_max_length: 20,
    where_is_my_friends_user_tag_max_displayed: 5,
  });
  needs.user();

  const api = {
    proposals: [],
    endorsements: [],
  };

  needs.pretender((server, helper) => {
    server.get("/where-is-my-friends.json", () =>
      helper.response(locationResponse())
    );
    server.get("/where-is-my-friends/callout.json", () =>
      helper.response(locationResponse())
    );
    server.get("/where-is-my-friends/next-action.json", () =>
      helper.response({
        action_type: "empty",
      })
    );
    server.post("/where-is-my-friends/events.json", () =>
      helper.response({ success: "OK" })
    );
    server.get("/where-is-my-friends/locations/nearby.json", () =>
      helper.response(nearbyResponse())
    );

    server.get("/where-is-my-friends/user-tags/mine.json", () =>
      helper.response({
        accepting_user_tags: true,
        pending: [
          {
            id: 1,
            label: "聊得来",
            status: "pending",
            proposer: { id: 2, username: "friend", name: "Friend" },
          },
        ],
        managed: [],
      })
    );

    server.put("/where-is-my-friends/user-tags/1/approve.json", () =>
      helper.response({
        user_tag: {
          id: 1,
          label: "聊得来",
          status: "approved",
          proposer: { id: 2, username: "friend", name: "Friend" },
        },
      })
    );

    server.post("/where-is-my-friends/user-tags.json", (request) => {
      const label = request.requestBody;
      api.proposals.push(label);
      return helper.response({
        user_tag: { id: 99, label: "靠谱", status: "pending" },
      });
    });

    server.post("/where-is-my-friends/user-tags/11/endorse.json", () => {
      api.endorsements.push("endorse");
      return helper.response({
        user_tag: {
          id: 11,
          label: "热心肠",
          endorser_count: 4,
          endorsed_by_me: true,
        },
      });
    });
  });

  test("shows approved tags with endorse buttons on nearby member cards", async function (assert) {
    await visit("/where-is-my-friends");

    assert.dom('[data-test-user-tag="热心肠"]').exists();
    assert.dom('[data-test-user-tag-endorse="热心肠"]').containsText("3");
  });

  test("endorses an approved tag and updates the count", async function (assert) {
    await visit("/where-is-my-friends");
    await click('[data-test-user-tag-endorse="热心肠"]');

    assert.strictEqual(api.endorsements.length, 1);
    assert.dom('[data-test-user-tag-endorse="热心肠"]').containsText("4");
  });

  test("proposes a new tag through the dialog", async function (assert) {
    await visit("/where-is-my-friends");
    await click('[data-test-user-tag-propose="friend"]');
    await fillIn("[data-test-user-tag-input]", "靠谱");
    await click("[data-test-user-tag-propose-submit]");

    assert.strictEqual(api.proposals.length, 1);
  });

  test("approves a pending tag from the inbox page", async function (assert) {
    await visit("/where-is-my-friends/tags");

    assert.dom('[data-test-user-tag-pending-item="聊得来"]').exists();
    await click('[data-test-user-tag-approve="聊得来"]');

    assert.dom("[data-test-user-tag-pending-empty]").exists();
    assert.dom('[data-test-user-tag-managed-item="聊得来"]').exists();
  });
});
