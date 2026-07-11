import { module, test } from "qunit";
import {
  providerLabel,
  resolveMapProvider,
} from "discourse/plugins/where-is-my-friends/discourse/lib/where-is-my-friends-maps";

module("Unit | where-is-my-friends | map provider", function () {
  test("OpenStreetMap is the default", function (assert) {
    assert.strictEqual(resolveMapProvider({}), "openstreetmap");
    assert.strictEqual(providerLabel("openstreetmap"), "OpenStreetMap");
  });

  test("a selected commercial provider without its browser key falls back", function (assert) {
    assert.strictEqual(resolveMapProvider({ map_provider: "amap" }), "openstreetmap");
    assert.strictEqual(resolveMapProvider({ map_provider: "baidu" }), "openstreetmap");
  });

  test("a commercial provider is used only with its matching browser key", function (assert) {
    assert.strictEqual(
      resolveMapProvider({ map_provider: "amap", amap_api_key: "browser-key" }),
      "amap"
    );
    assert.strictEqual(
      resolveMapProvider({ map_provider: "baidu", baidu_api_key: "browser-key" }),
      "baidu"
    );
  });
});
