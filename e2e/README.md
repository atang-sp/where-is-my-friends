# Local Friends Playwright suite

These tests run against real development Rails/Ember services and real plugin endpoints. They do not mock HTTP responses. Browser geolocation permission is the only browser capability controlled by Playwright.

From the Discourse checkout:

```bash
d/rake db:migrate
d/rails runner plugins/where-is-my-friends/e2e/setup.rb
d/dev --only rails
```

In another terminal:

```bash
d/dev --only ember
```

Then install and run from the plugin directory:

```bash
cd plugins/where-is-my-friends/e2e
pnpm install --ignore-workspace --frozen-lockfile
pnpm exec playwright install chromium
pnpm exec playwright test
```

The setup script resets only the four `admin`, `shanghai_one`, `shanghai_two`, and `empty_city` test accounts and the exact development login-rate-limit keys used by this suite. Playwright's global setup logs in each account once and stores ignored session state under `.auth/`; individual tests still use real Rails sessions and plugin endpoints. Re-run the Ruby setup before each full E2E run so the serial onboarding/removal scenarios start from a known state.

Override the server with `BASE_URL=http://...` when needed. Traces, screenshots, and video are retained only for failures under `test-results/`.
