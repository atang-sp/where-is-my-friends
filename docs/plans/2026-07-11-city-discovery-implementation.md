# City-first Local Discovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a privacy-safe, city-first local discovery experience with optional GPS/map distance bands, measurable connection actions, current Discourse compatibility, and real-browser Playwright coverage.

**Architecture:** The server owns all discovery boundaries: every active record has a normalized city, optional precise coordinates never leave the server, and nearby queries use only the authenticated user's stored record. A native Discourse/GJS page renders explicit setup, ready, empty, and error states and sends allowlisted privacy-safe funnel events. Model/request tests establish the contracts before implementation; QUnit and Playwright cover the rendered experience.

**Tech Stack:** Discourse Rails engine, PostgreSQL, RSpec, Ember/Glimmer GJS, QUnit acceptance tests, SCSS, Docker Discourse development environment, Playwright Test.

---

### Task 1: Provision the real Discourse test environment

**Files:**
- External checkout: `/home/atang/.cache/discourse-dev/where-is-my-friends/discourse`
- Move worktree to: `/home/atang/.cache/discourse-dev/where-is-my-friends/discourse/plugins/where-is-my-friends`

**Step 1: Clone current Discourse**

Run:

```bash
git clone --depth 1 https://github.com/discourse/discourse.git \
  /home/atang/.cache/discourse-dev/where-is-my-friends/discourse
```

Expected: checkout contains `d/boot_dev`, `bin/rspec`, and `frontend/`.

**Step 2: Move the isolated plugin worktree under Discourse**

Run from the plugin source repository:

```bash
git worktree move \
  /home/atang/.config/superpowers/worktrees/where-is-my-friends/city-discovery \
  /home/atang/.cache/discourse-dev/where-is-my-friends/discourse/plugins/where-is-my-friends
```

Expected: `git worktree list` shows `feat/city-discovery` at the plugin path.

**Step 3: Boot and migrate the development/test databases**

Run from the Discourse checkout:

```bash
d/boot_dev --init
d/rake db:migrate
d/rake db:migrate RAILS_ENV=test
```

Expected: all commands exit 0 and the plugin migrations load.

**Step 4: Run the empty baseline test target**

Run:

```bash
d/rake plugin:spec["where-is-my-friends"]
```

Expected: command loads the plugin successfully; initially it reports no plugin specs rather than a boot error.

No commit: this task changes only the external test environment.

### Task 2: Add the city-first location domain model

**Files:**
- Create: `db/migrate/20260711000001_add_city_discovery_fields.rb`
- Create: `app/jobs/scheduled/prune_where_is_my_friends_data.rb`
- Create: `spec/models/user_location_spec.rb`
- Modify: `app/models/user_location.rb`
- Modify: `config/settings.yml`
- Modify: `lib/where_is_my_friends/engine.rb`

**Step 1: Write failing model specs**

Cover these observable behaviors:

```ruby
describe UserLocation do
  it "normalizes Shanghai city variants to one city key"
  it "allows city mode without coordinates"
  it "requires coordinates for gps and map modes"
  it "excludes expired locations from active discovery"
  it "returns only distance bands, never an exact distance"
  it "clamps discovery result limits to 200"
end
```

Use real `Fabricate(:user)` records and freeze time for expiry assertions.

**Step 2: Run the specs and verify RED**

Run:

```bash
d/rspec plugins/where-is-my-friends/spec/models/user_location_spec.rb
```

Expected: failures mention missing city fields, normalization, active scope, and distance-band behavior.

**Step 3: Add the migration and minimal model behavior**

The migration must:

```ruby
change_column_null :user_locations, :latitude, true
change_column_null :user_locations, :longitude, true
add_column :user_locations, :city, :string
add_column :user_locations, :city_key, :string
add_column :user_locations, :region, :string
add_column :user_locations, :discovery_mode, :string, null: false, default: "city"
add_column :user_locations, :expires_at, :datetime
add_index :user_locations, %i[city_key enabled expires_at], name: "idx_user_locations_discovery"
```

The model must expose `normalize_city`, `active_for_discovery`,
`upsert_city_location`, `upsert_precise_location`, and `distance_band_to`.
Supported modes are exactly `city`, `gps`, and `map`. The default expiry comes
from `where_is_my_friends_location_ttl_days`, clamped to 1..365 days.

The scheduled job destroys expired locations and old analytics rows rather than
merely disabling them.

**Step 4: Run migrations and verify GREEN**

Run:

```bash
d/rake db:migrate RAILS_ENV=test
d/rspec plugins/where-is-my-friends/spec/models/user_location_spec.rb
```

Expected: all model examples pass.

**Step 5: Commit**

```bash
git add app/models app/jobs db/migrate config/settings.yml lib spec/models
git commit -m "feat: add city-first location model"
```

### Task 3: Secure and simplify the discovery API

**Files:**
- Create: `spec/requests/where_is_my_friends/locations_controller_spec.rb`
- Modify: `app/controllers/where_is_my_friends/locations_controller.rb`
- Modify: `app/serializers/user_location_serializer.rb`
- Modify: `config/routes.rb`
- Modify: `plugin.rb`
- Delete: `app/views/where_is_my_friends/locations/index.html.erb`

**Step 1: Write failing request specs**

Cover:

```ruby
it "requires login for every endpoint"
it "returns setup state without exposing coordinates"
it "saves city mode and returns ready state"
it "rejects precise mode without coordinates"
it "ignores client search coordinates and uses the current user's stored location"
it "excludes the current user and expired users"
it "returns distance bands without exact distances or coordinates"
it "does not serialize arbitrary user custom fields"
it "destroys a location on removal"
it "returns an explicit empty state"
```

Also assert that response JSON contains none of `latitude`, `longitude`,
`location_accuracy`, raw internal custom-field keys, or exception backtraces.

**Step 2: Verify RED**

Run:

```bash
d/rspec plugins/where-is-my-friends/spec/requests/where_is_my_friends/locations_controller_spec.rb
```

Expected: current API contract fails coordinate confidentiality, stored-origin,
field allowlisting, destructive removal, and explicit-state assertions.

**Step 3: Implement the minimal API contract**

Use only the engine routes under `/where-is-my-friends`. Remove duplicate
application `/api` routes and the patched `ListController` action. The nearby
action accepts optional gender/attribute/sort filters but never coordinates.

Serialize only core profile attributes plus explicitly configured public user
field IDs. Return `distance_band`, `city`, `region`, and action URLs; do not
return any location record or exact distance.

Replace broad `rescue => e` responses with translated generic errors and
structured validation errors. Remove the IP location endpoint and every raw
coordinate log line.

**Step 4: Verify GREEN and query count**

Run:

```bash
d/rspec plugins/where-is-my-friends/spec/requests/where_is_my_friends/locations_controller_spec.rb
d/rake plugin:spec["where-is-my-friends"]
```

Expected: request suite passes with no coordinate leakage.

**Step 5: Commit**

```bash
git add plugin.rb config/routes.rb app/controllers app/serializers spec/requests
git add -u app/views
git commit -m "fix: enforce private server-side discovery"
```

### Task 4: Add privacy-safe adoption analytics

**Files:**
- Create: `db/migrate/20260711000002_create_where_is_my_friends_events.rb`
- Create: `app/models/where_is_my_friends_event.rb`
- Create: `spec/models/where_is_my_friends_event_spec.rb`
- Create: `spec/requests/where_is_my_friends/events_controller_spec.rb`
- Create: `app/controllers/where_is_my_friends/events_controller.rb`
- Modify: `app/controllers/where_is_my_friends/locations_controller.rb`
- Modify: `config/routes.rb`

**Step 1: Write failing event and stats specs**

Assert the eight design-approved event names, rejection of unknown events,
coarse result buckets (`zero`, `one_to_four`, `five_to_nineteen`,
`twenty_plus`), 90-day retention, no location fields in the schema/API, admin
authorization, completion rates, conversion rates, and seven-day return rate.

**Step 2: Verify RED**

Run:

```bash
d/rspec \
  plugins/where-is-my-friends/spec/models/where_is_my_friends_event_spec.rb \
  plugins/where-is-my-friends/spec/requests/where_is_my_friends/events_controller_spec.rb
```

Expected: missing model, table, routes, and endpoint failures.

**Step 3: Implement analytics and aggregate stats**

The event table contains only `user_id`, `event_name`, `location_mode`,
`result_bucket`, and timestamps. Add indexes for `(event_name, created_at)` and
`(user_id, created_at)`. The endpoint derives `user_id` from the authenticated
session and rejects all non-allowlisted parameters.

The admin stats response exposes only aggregate counts and rates. Active city
counts below `where_is_my_friends_aggregate_privacy_threshold` are returned as
`suppressed: true` without an exact count.

**Step 4: Verify GREEN**

Run the same RSpec files plus the full plugin suite. Expected: all pass.

**Step 5: Commit**

```bash
git add app/controllers app/models db/migrate config/routes.rb spec
git commit -m "feat: measure the local discovery funnel"
```

### Task 5: Build the city-first GJS experience

**Files:**
- Create: `assets/javascripts/discourse/components/where-is-my-friends-page.gjs`
- Create: `test/javascripts/acceptance/where-is-my-friends-test.js`
- Modify: `assets/javascripts/discourse/routes/where-is-my-friends.js`
- Modify: `assets/javascripts/discourse/initializers/where-is-my-friends.js`
- Modify: `assets/javascripts/discourse/where-is-my-friends-route-map.js`
- Delete: `assets/javascripts/discourse/controllers/where-is-my-friends.js`
- Delete: `assets/javascripts/discourse/templates/where-is-my-friends.hbs`

**Step 1: Write failing acceptance tests**

Use `pretender` request handlers and assert:

```javascript
test("first visit saves a city and automatically loads results")
test("returning visit loads results without a find button")
test("empty results render an actionable empty state")
test("errors are escaped plain text")
test("current user is never rendered")
test("page and results events fire only after visible states")
```

**Step 2: Verify RED**

Run:

```bash
d/qunit plugins/where-is-my-friends/test/javascripts/acceptance/where-is-my-friends-test.js
```

Expected: missing component and new-state assertions fail.

**Step 3: Implement the GJS page and native route**

Use tracked state, injected router/site-settings/current-user services, `fn`,
`on`, standard `DButton`, `DIcon`, and `LinkTo` components. Render setup,
loading, ready, empty, and error from explicit state values. Submit city and
region, then call the nearby endpoint automatically. Returning users trigger
nearby loading from route setup.

Do not use triple braces, manual modal backdrops, direct DOM lookup, classic
`.extend`, or a separate controller.

**Step 4: Verify GREEN**

Run the acceptance file and plugin JS tests. Expected: all pass.

**Step 5: Commit**

```bash
git add assets/javascripts test/javascripts
git commit -m "feat: add city-first local discovery page"
```

### Task 6: Restore optional GPS and map discovery safely

**Files:**
- Create: `assets/javascripts/discourse/components/location-mode-dialog.gjs`
- Create: `assets/javascripts/discourse/components/virtual-location-picker.gjs`
- Create: `test/javascripts/unit/components/virtual-location-picker-test.js`
- Modify: `assets/javascripts/discourse/components/where-is-my-friends-page.gjs`
- Modify: `assets/javascripts/discourse/lib/where-is-my-friends-geolocation.js`
- Modify: `assets/javascripts/discourse/lib/where-is-my-friends-maps.js`
- Modify: `config/settings.yml`
- Delete: `assets/javascripts/discourse/components/virtual-location-picker.js`
- Delete: `assets/javascripts/discourse/templates/components/virtual-location-picker.hbs`

**Step 1: Write failing advanced-mode tests**

Test GPS success, permission denial with immediate city-mode fallback, map
selection, missing provider key fallback to OSM, and submission without any
reverse-geocoder request.

**Step 2: Verify RED**

Run the unit component test and relevant acceptance tests. Expected: legacy
picker and modal behavior fail the native component and fallback contracts.

**Step 3: Implement native advanced-mode components**

Make OSM the default provider. Lazy-load the map only after the user opens the
advanced section. Treat Amap/Baidu keys as browser keys and expose them only when
the provider is selected; document domain restrictions. Do not call Nominatim
or the removed IP endpoint. Submit coordinates only in the POST body and clear
them from component state after success/cancel.

Use Discourse's dialog/modal primitives so focus, Escape, and keyboard actions
work. Keep city and optional region required regardless of advanced mode.

**Step 4: Verify GREEN**

Run the component, acceptance, and plugin JS suites. Expected: all pass.

**Step 5: Commit**

```bash
git add assets/javascripts config/settings.yml test/javascripts
git add -u assets/javascripts/discourse/templates/components
git commit -m "feat: add optional private distance modes"
```

### Task 7: Complete the connection loop, content, and responsive UI

**Files:**
- Modify: `assets/javascripts/discourse/components/where-is-my-friends-page.gjs`
- Modify: `assets/stylesheets/where-is-my-friends.scss`
- Modify: `config/locales/client.en.yml`
- Modify: `config/locales/client.zh_CN.yml`
- Modify: `config/locales/server.en.yml`
- Modify: `config/locales/server.zh_CN.yml`
- Modify: `test/javascripts/acceptance/where-is-my-friends-test.js`

**Step 1: Write failing interaction tests**

Assert profile, new-message, and city-topic search links; their analytics events;
filter hiding below ten results; filter behavior above ten results; expiry text;
update/remove controls; empty-state invitation; and translated accessible labels.

**Step 2: Verify RED**

Run the acceptance file. Expected: missing actions and presentation contracts
fail.

**Step 3: Implement the connection loop and rewrite styles**

Use Discourse route-aware links. The message URL is generated server-side or by
the current supported Discourse composer API after checking the current core
implementation. Topic search URL encodes the stored city label. Emit analytics
before navigation only after the click.

Replace the 1,300-line legacy stylesheet with component-scoped rules for a
single-column mobile layout, two-column desktop card grid, visible focus rings,
reduced-motion support, and Discourse color variables.

**Step 4: Verify GREEN**

Run acceptance tests, template lint, ESLint, and stylelint for plugin files.

**Step 5: Commit**

```bash
git add assets/stylesheets assets/javascripts config/locales test/javascripts
git commit -m "feat: complete local connection actions"
```

### Task 8: Add compatibility, full regression, and documentation coverage

**Files:**
- Create: `.discourse-compatibility`
- Create: `spec/jobs/prune_where_is_my_friends_data_spec.rb`
- Modify: `README.md`
- Modify: `VIRTUAL_LOCATION_GUIDE.md`
- Modify: `plugin.rb`
- Delete obsolete routes, imports, translations, and SCSS selectors discovered by lint

**Step 1: Write the scheduled-job regression spec**

Create expired/current locations and old/current events. Assert that one job run
deletes only expired/old rows.

**Step 2: Verify RED, implement, and verify GREEN**

Run the job spec before and after the minimal implementation. Then run:

```bash
d/rake plugin:spec["where-is-my-friends"]
d/qunit plugins/where-is-my-friends
bin/lint plugins/where-is-my-friends
```

Expected: server suite, JS suite, Ruby/JS/template/style lint all exit 0.

**Step 3: Update documentation**

Document city-first onboarding, optional precise modes, 30-day default expiry,
aggregate analytics, public browser-key restrictions, privacy guarantees,
settings, migrations, tests, and supported Discourse version. Remove obsolete IP
fallback and exact-distance claims. Align plugin and README versions.

**Step 4: Commit**

```bash
git add .discourse-compatibility README.md VIRTUAL_LOCATION_GUIDE.md plugin.rb spec app config assets
git commit -m "chore: harden compatibility and regression coverage"
```

### Task 9: Add and run Playwright end-to-end coverage

**Files:**
- Create: `e2e/package.json`
- Create: `e2e/playwright.config.js`
- Create: `e2e/setup.rb`
- Create: `e2e/city-discovery.spec.js`
- Create: `e2e/README.md`

**Step 1: Write Playwright tests before final UI verification**

Implement the eight design scenarios with web-first assertions. Use three seeded
accounts (`admin`, `shanghai_one`, `shanghai_two`) and a fourth empty-city user.
Intercept only browser geolocation for denial/success; do not mock plugin HTTP
responses.

**Step 2: Seed the development site and start services**

Run:

```bash
d/rails runner plugins/where-is-my-friends/e2e/setup.rb
d/rails s
d/dev --only ember
```

Expected: `http://localhost:3000` renders Discourse with the plugin enabled.

**Step 3: Install and run Playwright**

Run from `plugins/where-is-my-friends/e2e`:

```bash
pnpm install --frozen-lockfile
pnpm exec playwright install chromium
pnpm exec playwright test
```

Expected: all eight scenarios pass in desktop Chromium; the mobile project also
passes its responsive scenario. Preserve traces/screenshots only on failure.

**Step 4: Commit the reproducible E2E suite**

```bash
git add e2e
git commit -m "test: cover local discovery with Playwright"
```

### Task 10: Final audit, review, and merge

**Files:** No new behavior unless verification finds a defect.

**Step 1: Run every gate from a clean feature-branch state**

```bash
git status --short
d/rake plugin:spec["where-is-my-friends"]
d/qunit plugins/where-is-my-friends
bin/lint plugins/where-is-my-friends
cd plugins/where-is-my-friends/e2e && pnpm exec playwright test
```

Expected: clean status and every command exits 0.

**Step 2: Audit the objective requirement by requirement**

Confirm with source and test evidence: city-first default, optional GPS/map,
automatic results, actionable empty state, contact/topic actions, expiry,
privacy-safe API and analytics, no coordinate/custom-field leakage, current GJS
compatibility, multiple focused commits, and Playwright coverage against real
Discourse.

**Step 3: Review the branch diff and commit structure**

```bash
git log --oneline main..feat/city-discovery
git diff --check main...feat/city-discovery
git diff --stat main...feat/city-discovery
```

Expected: focused commits, no whitespace errors, no unrelated changes.

**Step 4: Merge only after all gates pass**

Return to `/home/atang/workspace/where-is-my-friends` and run:

```bash
git merge --no-ff feat/city-discovery
```

Expected: merge commit on `main`, no conflict. Re-run `git status --short` and
the essential plugin/Playwright gates against the merged commit before reporting
completion.

