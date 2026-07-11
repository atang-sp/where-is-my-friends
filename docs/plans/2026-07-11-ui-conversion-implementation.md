# Local Friends UI Conversion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve Local Friends discovery, city setup, member connections, and return paths with a privacy-safe conversion-focused UI.

**Architecture:** Keep the existing city-first API and analytics boundary. Add one native GJS topic-list outlet connector, consume the existing aggregate/suggestion payload on the Local Friends page, and reorganize existing actions without adding member-profile fields. Use QUnit and request specs for each contract before implementation, then extend the real-service Playwright suite.

**Tech Stack:** Discourse 2026.7 GJS/Glimmer, Ember services and modifiers, Discourse UI Kit, Ruby on Rails, RSpec, QUnit, SCSS, Playwright.

---

### Task 1: Deduplicate city suggestions by normalized key

**Files:**
- Modify: `spec/requests/where_is_my_friends/locations_controller_spec.rb`
- Modify: `app/controllers/where_is_my_friends/locations_controller.rb`

**Step 1: Write the failing request spec**

Add a setup-state example which creates active locations for `上海`, `上海市`,
and `北京`. Request `/where-is-my-friends.json` and assert that the suggestions
contain exactly one entry with `city_key: "上海"` plus one Beijing entry.

**Step 2: Run the focused spec and verify RED**

Run:

```bash
d/rspec plugins/where-is-my-friends/spec/requests/where_is_my_friends/locations_controller_spec.rb
```

Expected: FAIL because `distinct` retains both display labels for the same
normalized key.

**Step 3: Implement normalized-key deduplication**

Change `city_suggestions` to group active records by `city_key`, select one
stable display label per key, order by that label, and limit the final array to
20. Preserve the response shape:

```ruby
[{ city: "上海", city_key: "上海" }]
```

**Step 4: Run the focused spec and verify GREEN**

Expected: all location request examples pass.

**Step 5: Commit**

```bash
git add app/controllers/where_is_my_friends/locations_controller.rb \
  spec/requests/where_is_my_friends/locations_controller_spec.rb
git commit -m "fix: deduplicate local city suggestions"
```

### Task 2: Add a dismissible topic-list discovery entry

**Files:**
- Create: `assets/javascripts/discourse/connectors/above-main-container/local-friends-callout.gjs`
- Modify: `test/javascripts/acceptance/where-is-my-friends-test.js`
- Modify: `config/locales/client.en.yml`
- Modify: `config/locales/client.zh_CN.yml`
- Modify: `assets/stylesheets/where-is-my-friends.scss`

**Step 1: Write failing acceptance coverage**

Add tests that visit `/`, stub the existing state endpoint, and assert:

- a logged-in setup user sees a callout linking to `/where-is-my-friends`;
- an exact participant count is shown only when `suppressed` is false;
- a returning user gets view-oriented copy;
- clicking dismiss hides the callout for the current browser session;
- the callout does not appear on `/where-is-my-friends`.

Clear the callout's `sessionStorage` key in test setup/teardown.

**Step 2: Run the acceptance file and verify RED**

Run:

```bash
CI=1 d/rake 'plugin:qunit[where-is-my-friends]'
```

Expected: FAIL because the outlet connector does not exist.

**Step 3: Implement the connector**

Create a native Glimmer connector which injects `router` and `currentUser`,
renders only on discovery/category topic-list routes, and loads
`/where-is-my-friends.json` once when inserted. Use `LinkTo` for the CTA and a
labelled `DButton` for dismissal. Persist dismissal in `sessionStorage`; do not
emit a `page_view` event from the callout.

Render privacy-safe social proof as either:

```text
12 members are already discovering local connections
```

or a generic threshold-safe message.

**Step 4: Add scoped responsive styles and translations**

Style the callout as a compact Discourse surface with one text block, one CTA,
and a low-emphasis dismiss control. It must fit a 390px viewport without
horizontal overflow.

**Step 5: Run the acceptance file and lint; verify GREEN**

Run the focused QUnit file and:

```bash
d/exec bin/lint plugins/where-is-my-friends
```

Expected: connector tests and all linters pass.

**Step 6: Commit**

```bash
git add assets/javascripts/discourse/connectors \
  assets/stylesheets/where-is-my-friends.scss \
  config/locales/client.en.yml config/locales/client.zh_CN.yml \
  test/javascripts/acceptance/where-is-my-friends-test.js
git commit -m "feat: surface local discovery on topic lists"
```

### Task 3: Shorten first-visit setup and show social proof

**Files:**
- Modify: `assets/javascripts/discourse/components/where-is-my-friends-page.gjs`
- Modify: `test/javascripts/acceptance/where-is-my-friends-test.js`
- Modify: `config/locales/client.en.yml`
- Modify: `config/locales/client.zh_CN.yml`
- Modify: `assets/stylesheets/where-is-my-friends.scss`

**Step 1: Write failing setup tests**

Assert that:

- a permitted exact participant count or a suppressed generic message appears;
- server city suggestions render as a `datalist` connected to the city input;
- region is initially collapsed for a new user;
- the region control opens it and its value is included in the existing save
  request;
- editing a saved location with a region opens the region field.

**Step 2: Run the focused QUnit file and verify RED**

Expected: the new social-proof, datalist, and region-disclosure assertions fail.

**Step 3: Implement the setup hierarchy**

Add a tracked `showRegion` initialized from the existing saved region. Render a
compact participation line before the form, connect `list` on the city input to
options from `@model.city_suggestions`, and place region behind a secondary
button. Keep city as the only required primary field and preserve automatic
result loading after save.

**Step 4: Refine the first viewport**

Reduce header size and vertical spacing. Keep the city input, primary CTA, and
privacy disclosure visible without scrolling on a typical mobile viewport.

**Step 5: Run QUnit and lint; verify GREEN**

Expected: focused acceptance tests and all linters pass.

**Step 6: Commit**

```bash
git add assets/javascripts/discourse/components/where-is-my-friends-page.gjs \
  assets/stylesheets/where-is-my-friends.scss \
  config/locales/client.en.yml config/locales/client.zh_CN.yml \
  test/javascripts/acceptance/where-is-my-friends-test.js
git commit -m "feat: streamline city discovery setup"
```

### Task 4: Reorganize results around connection and return paths

**Files:**
- Modify: `assets/javascripts/discourse/components/where-is-my-friends-page.gjs`
- Modify: `test/javascripts/acceptance/where-is-my-friends-test.js`
- Modify: `config/locales/client.en.yml`
- Modify: `config/locales/client.zh_CN.yml`
- Modify: `assets/stylesheets/where-is-my-friends.scss`

**Step 1: Write failing result-page tests**

Assert that a populated result page:

- displays the city and visible member count;
- always includes a measured local-topic link;
- gives the message action primary styling and profile secondary styling;
- hides advanced/update/remove controls until `Location settings` is opened;
- retains working update, GPS/map, and removal behavior after opening.

**Step 2: Run the focused QUnit file and verify RED**

Expected: count/topic/disclosure/action-hierarchy assertions fail.

**Step 3: Implement the new hierarchy**

Add a results heading row with count and the existing `full-page-search` link.
Swap member-card button emphasis. Wrap location management actions in a native
`details`/`summary` disclosure with translated labels and keep removal visibly
destructive inside it.

**Step 4: Update responsive styles**

Keep the heading row and actions usable on mobile, maintain focus rings, and
avoid hover-only affordances.

**Step 5: Run QUnit and lint; verify GREEN**

**Step 6: Commit**

```bash
git add assets/javascripts/discourse/components/where-is-my-friends-page.gjs \
  assets/stylesheets/where-is-my-friends.scss \
  config/locales/client.en.yml config/locales/client.zh_CN.yml \
  test/javascripts/acceptance/where-is-my-friends-test.js
git commit -m "feat: focus local results on connection"
```

### Task 5: Make empty, loading, and error states actionable

**Files:**
- Modify: `assets/javascripts/discourse/components/where-is-my-friends-page.gjs`
- Modify: `test/javascripts/acceptance/where-is-my-friends-test.js`
- Modify: `config/locales/client.en.yml`
- Modify: `config/locales/client.zh_CN.yml`
- Modify: `assets/stylesheets/where-is-my-friends.scss`

**Step 1: Write failing state tests**

Assert that:

- loading renders card skeletons and an accessible status;
- the empty state includes a working copy-invite action;
- copy success and failure produce translated live feedback;
- a server/network error without translated response text uses the translated
  generic fallback rather than hard-coded English.

Stub Discourse's `clipboardCopy` behavior at the module boundary or the browser
clipboard capability used by that utility.

**Step 2: Run the focused QUnit file and verify RED**

**Step 3: Implement state improvements**

Import `clipboardCopy` from `discourse/lib/utilities`. Copy the canonical
`/where-is-my-friends` URL from a user gesture, set a tracked feedback state,
and announce it with `role="status"`. Add three inert skeleton cards while
loading and use `i18n("where_is_my_friends.generic_error")` as the fallback.

**Step 4: Add reduced-motion-safe styles and translations**

Skeleton animation must stop under `prefers-reduced-motion: reduce`.

**Step 5: Run QUnit and lint; verify GREEN**

**Step 6: Commit**

```bash
git add assets/javascripts/discourse/components/where-is-my-friends-page.gjs \
  assets/stylesheets/where-is-my-friends.scss \
  config/locales/client.en.yml config/locales/client.zh_CN.yml \
  test/javascripts/acceptance/where-is-my-friends-test.js
git commit -m "feat: improve local discovery states"
```

### Task 6: Extend real-service Playwright coverage

**Files:**
- Modify: `e2e/city-discovery.spec.js`
- Modify: `e2e/README.md`

**Step 1: Add end-to-end scenarios**

Before final verification, cover:

- topic-list callout visibility and navigation;
- privacy-safe participant proof and city suggestions;
- optional region reveal;
- populated results count and persistent local-topic action;
- location-settings disclosure;
- invite-link copying;
- updated 390px mobile first viewport and no horizontal overflow.

Keep real Rails sessions and endpoints. Only browser capabilities such as
clipboard permissions may be controlled by Playwright.

**Step 2: Seed and run Playwright**

Run:

```bash
d/rails runner plugins/where-is-my-friends/e2e/setup.rb
docker exec -u discourse:discourse \
  -w /src/plugins/where-is-my-friends/e2e \
  -e PLAYWRIGHT_BROWSERS_PATH=/home/discourse/.cache/ms-playwright \
  discourse_dev ./node_modules/.bin/playwright test
```

Expected: every desktop and mobile scenario passes.

**Step 3: Commit**

```bash
git add e2e/city-discovery.spec.js e2e/README.md
git commit -m "test: cover local discovery conversion UI"
```

### Task 7: Full verification and review

**Files:** No behavior changes unless verification finds a defect.

**Step 1: Verify a clean focused commit history**

Run:

```bash
git status --short
git log --oneline main..HEAD
git diff --check main...HEAD
```

**Step 2: Run every plugin gate**

```bash
d/rake 'compatibility:validate[plugins/where-is-my-friends/.discourse-compatibility]'
d/rake 'plugin:spec[where-is-my-friends]'
CI=1 d/rake 'plugin:qunit[where-is-my-friends]'
d/exec bin/lint plugins/where-is-my-friends
```

Expected: compatibility valid, all RSpec/QUnit examples pass with no
deprecations, and all lint stages pass.

**Step 3: Run the full Playwright suite again**

Re-seed development data and run the exact Task 6 command. Expected: all
desktop/mobile scenarios pass against real Rails and Ember services.

**Step 4: Review privacy and scope**

Confirm no coordinate, exact-distance, last-seen, biography, or arbitrary
custom-field data was added. Confirm the topic-list callout does not emit fake
page-view analytics and never appears for logged-out users or on the Local
Friends page.

**Step 5: Present branch integration options**

Keep `main` untouched until the user chooses local merge, PR, or branch
preservation after reviewing the verified result.
