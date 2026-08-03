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

When the suite itself runs inside a container with browser user namespaces
disabled, set `DISCOURSE_DISABLE_BROWSER_SANDBOX=1`; this only adds Chromium's
`--no-sandbox` launch argument to the development test process.

To reuse an already installed Chromium-compatible browser instead of
downloading Playwright's managed build:

```bash
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/path/to/chrome pnpm exec playwright test
```

If the browser reaches the container through a non-default Docker gateway, pass
that address while seeding:

```bash
LOCAL_FRIENDS_E2E_CLIENT_IP=172.18.0.1 \
  d/rails runner plugins/where-is-my-friends/e2e/setup.rb
```

The setup script refuses to run outside the Rails development environment. It resets only the seven `admin`, `shanghai_one`, `shanghai_two`, `empty_city`, `city_entry`, `dynamics_one`, and `dynamics_two` test accounts, their Local Friends interest/location records, dynamics owned by the two dynamics accounts, one exact interest test topic, and the exact development login-rate-limit keys used by this suite. Playwright's global setup logs in each account once and stores ignored session state under `.auth/`; individual tests still use real Rails sessions and plugin endpoints. Re-run the Ruby setup before each full E2E run so the serial onboarding/removal and dynamics scenarios start from a known state.

Override the server with `BASE_URL=http://...` when needed. Traces, screenshots, and video are retained only for failures under `test-results/`.

The suite covers interest prompting, private-by-default selection, explainable
topic/member recommendations and dismissal, plus the topic-list local discovery
entry, privacy-safe participation proof, city suggestions, optional region
setup, populated and empty result paths, invite copying,
profile/message/topic actions, location settings, GPS/map behavior, removal,
mobile layout, and aggregate admin metrics.
The personal dynamics suite additionally covers two-member publishing and
viewing, the lazy homepage group, member-card previews, native replies,
anonymous denial, media rejection, ordinary-topic-list exclusion, and desktop,
tablet, and mobile layouts.
