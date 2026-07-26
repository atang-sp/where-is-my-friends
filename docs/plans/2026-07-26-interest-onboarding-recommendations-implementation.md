# Interest onboarding implementation plan

**Goal:** Ship a privacy-safe interest cold start that immediately recommends
five topics and three people, then release and deploy it.

**Architecture:** A deep `WhereIsMyFriends::RecommendationEngine` owns
catalogue construction, permission-safe topic retrieval, member eligibility,
ranking, reasons, and serialization behind one `call` interface. A separate
interest profile module owns private preferences and dismissals. Rails request
interfaces are the server test seam; one native GJS page and a small prompt are
the browser interface.

## Tracer slices

1. Add profile/interest/dismissal persistence and a request that validates and
   saves three to five visible tags.
2. Return permission-safe topic recommendations immediately after save.
3. Add opt-in member recommendations with public contribution reasons and
   ignore/mute filtering.
4. Add dismissal, skip, edit, publish, recommendable, and disable/clear
   controls.
5. Add the GJS route, onboarding page, prompt, navigation entry, styles, and
   translations.
6. Extend privacy-safe aggregate events and administrator diagnostics, and
   derive seven-day public-interaction and first-reply rates without storing
   content or recommendation target IDs.
7. Add real-browser onboarding coverage, documentation, version bump, release,
   and deployment.
