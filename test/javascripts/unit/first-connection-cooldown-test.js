import { module, test } from "qunit";
import {
  FIRST_CONNECTION_COOLDOWN_KEY,
  FIRST_CONNECTION_COOLDOWN_MS,
  firstConnectionCooldownActive,
  startFirstConnectionCooldown,
} from "discourse/plugins/where-is-my-friends/discourse/lib/first-connection-cooldown";

function memoryStorage() {
  const values = new Map();
  return {
    getItem(key) {
      return values.get(key) ?? null;
    },
    setItem(key, value) {
      values.set(key, value);
    },
    values,
  };
}

module("Unit | where-is-my-friends | first connection cooldown", function () {
  test("stores only a dismissal timestamp and expires after seven days", function (assert) {
    const storage = memoryStorage();
    const dismissedAt = Date.UTC(2026, 7, 8, 12);

    startFirstConnectionCooldown({ now: dismissedAt, storage });

    assert.deepEqual(
      [...storage.values.keys()],
      [FIRST_CONNECTION_COOLDOWN_KEY]
    );
    assert.strictEqual(
      storage.getItem(FIRST_CONNECTION_COOLDOWN_KEY),
      String(dismissedAt)
    );
    assert.true(
      firstConnectionCooldownActive({
        now: dismissedAt + FIRST_CONNECTION_COOLDOWN_MS - 1,
        storage,
      })
    );
    assert.false(
      firstConnectionCooldownActive({
        now: dismissedAt + FIRST_CONNECTION_COOLDOWN_MS,
        storage,
      })
    );
  });

  test("unavailable or malformed storage fails open", function (assert) {
    const malformed = memoryStorage();
    malformed.setItem(FIRST_CONNECTION_COOLDOWN_KEY, "target-content");
    const unavailable = {
      getItem() {
        throw new Error("unavailable");
      },
    };

    assert.false(firstConnectionCooldownActive({ storage: malformed }));
    assert.false(firstConnectionCooldownActive({ storage: unavailable }));
  });
});
