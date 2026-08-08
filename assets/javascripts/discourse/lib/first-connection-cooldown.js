export const FIRST_CONNECTION_COOLDOWN_KEY =
  "where-is-my-friends:first-connection-dismissed-at";
export const FIRST_CONNECTION_COOLDOWN_MS = 7 * 24 * 60 * 60 * 1000;

function browserStorage() {
  return globalThis.localStorage;
}

export function firstConnectionCooldownActive({
  now = Date.now(),
  storage,
} = {}) {
  try {
    const activeStorage = storage ?? browserStorage();
    const dismissedAt = Number(
      activeStorage?.getItem(FIRST_CONNECTION_COOLDOWN_KEY)
    );
    return (
      Number.isFinite(dismissedAt) &&
      dismissedAt > 0 &&
      dismissedAt + FIRST_CONNECTION_COOLDOWN_MS > now
    );
  } catch {
    return false;
  }
}

export function startFirstConnectionCooldown({
  now = Date.now(),
  storage,
} = {}) {
  try {
    const activeStorage = storage ?? browserStorage();
    activeStorage?.setItem(FIRST_CONNECTION_COOLDOWN_KEY, String(now));
  } catch {
    // Storage is optional. The component's tracked state still hides this view.
  }
}
