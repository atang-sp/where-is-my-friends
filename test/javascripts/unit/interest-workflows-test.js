import { module, test } from "qunit";
import InvitationInbox from "discourse/plugins/where-is-my-friends/discourse/lib/invitation-inbox";
import PreferenceRecommendationSession from "discourse/plugins/where-is-my-friends/discourse/lib/preference-recommendation-session";

module("Unit | where-is-my-friends | interest workflows", function () {
  test("invitation failures stay isolated from preference recommendations", async function (assert) {
    const preference = new PreferenceRecommendationSession({
      model: {
        state: "complete",
        profile: {
          interests: [],
          purpose: "learn",
          recommendable: true,
          show_interests_publicly: false,
        },
        catalogue: [],
        recommended_topics: [{ id: 1 }],
        recommended_users: [],
      },
      currentUser: {},
      telemetry: { record: async () => true },
    });
    const invitations = new InvitationInbox({
      transport: async (url) => {
        if (url.endsWith("practice-invitations.json")) {
          throw { responseJSON: { errors: ["Invitations unavailable"] } };
        }
        return { bookmarks: [] };
      },
    });

    await invitations.intents.initialize();

    assert.strictEqual(invitations.view.error, "Invitations unavailable");
    assert.false(invitations.view.loading);
    assert.strictEqual(preference.view.error, null);
    assert.false(preference.view.loading);
    assert.true(preference.view.results.recommendations.hasRecommendations);
    assert.deepEqual(Object.keys(preference.view).sort(), [
      "editing",
      "editor",
      "error",
      "loading",
      "results",
      "state",
    ]);
    assert.deepEqual(Object.keys(invitations.view).sort(), [
      "error",
      "loading",
      "state",
      "success",
    ]);
    assert.deepEqual(Object.keys(preference.view.results).sort(), [
      "invitationsEnabled",
      "loading",
      "recommendations",
    ]);
    assert.deepEqual(Object.keys(preference.editorState).sort(), [
      "catalogue",
      "privacy",
      "purpose",
      "selection",
      "status",
    ]);
    assert.deepEqual(Object.keys(preference.intents.editor).sort(), [
      "changeDraft",
      "submit",
      "toggleInterest",
    ]);
    assert.deepEqual(Object.keys(preference.intents.results).sort(), [
      "dismiss",
      "manage",
      "trackOpen",
    ]);
    assert.deepEqual(Object.keys(invitations.view.state).sort(), [
      "busy",
      "composer",
      "inbox",
      "legacy",
    ]);
    assert.deepEqual(Object.keys(invitations.intents).sort(), [
      "changeDraft",
      "close",
      "initialize",
      "open",
      "respond",
      "send",
    ]);
  });
});
