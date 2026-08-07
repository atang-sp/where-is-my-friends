import { module, test } from "qunit";
import LocationDiscoveryWorkflow from "discourse/plugins/where-is-my-friends/discourse/lib/location-discovery-workflow";

module("Unit | where-is-my-friends | location discovery workflow", function () {
  test("normalizes nearby results behind compact view and intent seams", async function (assert) {
    const requests = [];
    const workflow = new LocationDiscoveryWorkflow({
      model: {
        state: "ready",
        location: {
          city: "Shanghai",
          discovery_mode: "city",
          discovery_radius_km: 100,
        },
        current_user: { username: "self" },
        settings: {},
        filterable_fields: [],
      },
      currentUser: { username: "self", user_option: {} },
      siteSettings: { chat_enabled: false },
      router: { currentRoute: { queryParams: {} } },
      telemetry: { record: async () => true },
      transport: async (...request) => {
        requests.push(request);
        return {
          users: [
            { username: "self", city: "Shanghai" },
            { username: "friend", city: "Shanghai" },
          ],
          city_groups: [],
          results_limited: true,
        };
      },
      currentLocation: { search: "", href: "https://example.test/" },
    });

    await workflow.intents.initialize();

    assert.deepEqual(requests, [
      ["/where-is-my-friends/locations/nearby.json", { data: {} }],
    ]);
    assert.strictEqual(workflow.view.mode, "results");
    assert.strictEqual(workflow.view.discoveryState, "ready");
    assert.true(workflow.view.results.hasUsers);
    assert.true(workflow.view.results.resultsLimited);
    assert.deepEqual(
      workflow.view.results.displayCityGroups[0].users.map(
        (user) => user.username
      ),
      ["friend"]
    );
    assert.deepEqual(Object.keys(workflow.view).sort(), [
      "discoveryState",
      "error",
      "mode",
      "results",
      "setup",
    ]);
    assert.strictEqual(workflow.intents, workflow.intents);
  });
});
