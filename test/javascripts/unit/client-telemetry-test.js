import { module, test } from "qunit";
import { createClientTelemetry } from "discourse/plugins/where-is-my-friends/discourse/lib/client-telemetry";

module("Unit | where-is-my-friends | client telemetry", function () {
  test("maps allowlisted recommendation context without leaking target data", async function (assert) {
    const requests = [];
    const telemetry = createClientTelemetry(
      { surface: "homepage" },
      async (...request) => requests.push(request)
    );

    const recorded = await telemetry.record("recommendation_impression", {
      recommendationGroup: "people",
      recommendation: {
        id: 42,
        username: "private-member",
        candidate_source: "interest",
        rank: 2,
        latest_dynamic: { raw: "private text" },
      },
      algorithmVersion: "participation_v1",
      resultCount: 3,
      city: "上海",
    });

    assert.true(recorded);
    assert.deepEqual(requests, [
      [
        "/where-is-my-friends/events.json",
        {
          type: "POST",
          data: {
            event_name: "recommendation_impression",
            surface: "homepage",
            recommendation_group: "people",
            candidate_source: "interest",
            rank: 2,
            algorithm_version: "participation_v1",
            result_count: 3,
            has_dynamic_preview: true,
          },
        },
      ],
    ]);
  });

  test("drops unknown events before transport", async function (assert) {
    let requests = 0;
    const telemetry = createClientTelemetry({}, async () => requests++);

    assert.false(await telemetry.record("private_target_opened"));
    assert.strictEqual(requests, 0);
  });

  test("transport failures remain best-effort", async function (assert) {
    const telemetry = createClientTelemetry({}, async () => {
      throw new Error("offline");
    });

    assert.false(await telemetry.record("page_view"));
  });

  test("allows first connection events with coarse context only", async function (assert) {
    const requests = [];
    const telemetry = createClientTelemetry(
      { surface: "homepage" },
      async (...request) => requests.push(request)
    );

    assert.true(
      await telemetry.record("first_connection_topic_opened", {
        recommendationGroup: "topics",
        algorithmVersion: "first_connection_v1",
        topicId: 42,
        title: "private target title",
      })
    );
    assert.deepEqual(requests[0][1].data, {
      event_name: "first_connection_topic_opened",
      surface: "homepage",
      recommendation_group: "topics",
      algorithm_version: "first_connection_v1",
    });
  });
});
