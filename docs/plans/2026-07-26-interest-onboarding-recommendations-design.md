# Interest onboarding and member recommendations

## Objective

Increase meaningful forum participation by helping new and existing members
discover relevant public topics and people. The system must deliver useful
recommendations immediately after a short, optional onboarding flow without
turning private preferences into public profile data or notification
subscriptions.

The primary success metric is the percentage of onboarded members who create a
new public interaction within seven days. Supporting metrics are onboarding
completion, recommendation opens, first replies, and seven-day return.

## Onboarding contract

- Every signed-in member without a completed or dismissed interest profile sees
  a dismissible onboarding prompt.
- The prompt links to a dedicated interest page and never blocks normal forum
  use.
- Members choose three to five interests when at least three interests are
  available. If the visible catalogue contains fewer than three entries, all
  available entries are sufficient.
- Members choose one current purpose: learn, share, connect, ask, help, or
  browse.
- Saving immediately returns up to five visible public topics and three
  recommendable members.
- Members may skip onboarding, edit their choices later, or disable and clear
  personalization.

## Interest catalogue

- Administrators may configure up to twenty Discourse tag names.
- If no list is configured, the catalogue is derived from tags on the current
  member's visible recent topics.
- Tag visibility and category permissions are always applied for the signed-in
  member.
- Choosing an interest does not watch, track, mute, or otherwise change
  Discourse notification preferences.

## Topic recommendations

- Topics come from the member's visible, listable, non-private Discourse topic
  query and match at least one chosen interest.
- Muted categories/tags and ignored topic authors follow core Discourse
  filtering.
- Recommendations exclude topics the member dismissed.
- Each result contains only link-safe public metadata and the matching interest
  reasons.

## Member recommendations

- Candidates must have completed interest onboarding, explicitly allow being
  recommended, be active, non-staged, non-suspended, and recently seen.
- Candidates exclude the current member and both directions of Discourse
  ignore/mute relationships.
- Candidate scoring uses only visible public topic contributions, purpose
  complementarity, recent activity, and deterministic diversity.
- A recommendation reason may cite only visible public contributions and
  public profile information. It must never reveal the candidate's private
  interest selections or purpose.
- Each member card includes up to two representative visible topics.
- Dismissed members do not reappear.

## Privacy and control

- Interest selections and purpose are private by default.
- A member may explicitly publish selected interests on their profile and user
  card; purpose is always private.
- A member separately controls whether they may be recommended to other
  members.
- Disabling personalization clears interest rows and dismissal rows and leaves
  a dismissed profile marker so the prompt does not immediately return.
- Recommendation analytics contain only allowlisted event names and coarse
  counts, never interest names, tag IDs, target IDs, usernames, locations, or
  content.
- Seven-day public interaction and first-reply rates are derived from public
  regular posts within each onboarding completion window. Private messages,
  hidden/deleted posts, and read-restricted categories are excluded; no
  interaction target is persisted by the plugin.

## User experience

- The interest page uses current Discourse GJS and UI Kit controls, translated
  English and Chinese copy, keyboard-accessible toggle buttons, explicit
  loading/error/empty states, and responsive layouts.
- Recommendation cards lead first to public topics or profiles. Following,
  messaging, and notification changes are left to native Discourse surfaces.
- A completed member can return from the community navigation and edit
  interests at any time.

## Delivery evidence

- Request/model specs cover catalogue visibility, validation, immediate
  recommendations, permission filtering, ignore/mute filtering, dismissals,
  privacy serialization, skip, and disable/clear.
- QUnit covers the prompt, onboarding choices, immediate results, edit,
  dismissal, empty/error states, and privacy controls.
- Playwright covers a first-login prompt through saved preferences and rendered
  recommendations against real Rails and Ember services.
- Migrations pass in development and test.
- Full plugin RSpec, QUnit, lint, and Playwright pass before release.
- Release requires a committed version bump, merged remote code, Git tag and
  GitHub release, production deployment, migrations, and a production health
  check.
