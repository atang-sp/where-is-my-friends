# Local Friends UI conversion design

## Objective

Increase discovery-page visits, city setup completion, member connections, and
return visits without making precise location more prominent. The redesign must
work without a pre-existing analytics baseline and preserve the current privacy
boundary.

## Chosen direction

Use a conversion-first refinement of the existing city-first experience.

Two broader alternatives were considered:

- A local-community feed that mixes members, topics, and events would create a
  stronger return loop, but it requires new content queries and ranking rules.
- A map-led directory would be visually distinctive, but it would reintroduce
  location anxiety and loading cost before users see any value.

The conversion-first direction is the smallest change that addresses the known
funnel gaps. A community feed can follow once the existing aggregate metrics
show enough participation.

## Discovery entry

Keep the existing navigation tab and add a compact callout in Discourse's
`above-main-container` outlet on topic-list and discovery routes. The callout is
shown only to logged-in users, never on the Local Friends route itself, and can
be dismissed for the browser session.

The callout loads the existing coordinate-free state endpoint. It changes its
copy and action based on whether the user has configured a city:

- Setup users see a short value statement and a `Set my city` action.
- Returning users see a `View local members` action.
- An exact active-participant count is displayed only when the existing privacy
  threshold permits it; otherwise the copy remains generic.

The callout does not emit a page-view event. A page view still means the user
actually opened Local Friends.

## First-visit conversion

Reduce the visual height of the page header so the city field and primary CTA
remain in the first viewport. Display privacy-safe participation proof above the
form and connect the city field to the city suggestions already returned by the
server.

Only city remains visually primary. Region is revealed through a secondary
`Add region` control and stays open when editing a saved non-empty region. The
privacy disclosure remains next to the submit action. City suggestions are
deduplicated by normalized city key so variants such as `上海` and `上海市` do
not compete in the list.

## Results and return loop

The results header states the city and visible member count. A persistent
`Browse local topics` action appears beside it even when members are available,
giving the page a content path on every visit.

Member cards keep the minimal public data contract. Message becomes the primary
action and profile becomes secondary. No biography, last-seen timestamp,
arbitrary profile field, or precise coordinate is added.

Location management moves into a native disclosure labelled `Location
settings`. Advanced distance bands, city editing, and removal remain available
but no longer compete with member discovery. Removal remains visually
destructive inside the disclosure.

## Empty, loading, and error states

The empty state keeps the local-topic action and gains a real `Copy invite link`
button using Discourse's clipboard utility. Successful or failed copy feedback
is translated and announced with a live status message.

Loading results uses lightweight card skeletons plus a screen-reader status.
Reduced-motion preferences disable animation. The generic network fallback is
translated rather than hard-coded in English.

## Analytics and rollout

No new analytics event names are required. The existing metrics answer the
first rollout questions:

- `unique_page_visitors` measures whether the new topic-list callout improves
  discovery.
- `setup_completion_rate` measures the shorter setup flow.
- result buckets distinguish UI conversion from insufficient same-city density.
- profile, message, local-topic, and seven-day return rates measure result-page
  usefulness.

The initial release should compare 7- and 30-day windows after deployment. Low
page visits indicate an entry problem; low setup completion indicates a form
problem; high setup completion with empty results indicates a density or city
normalization problem rather than a visual problem.

## Testing

QUnit acceptance coverage will verify the topic-list callout, session dismissal,
privacy-safe social proof, deduplicated city suggestions, optional region,
result hierarchy, clipboard feedback, skeleton state, and translated errors.
Server request specs will verify normalized city-suggestion deduplication.

Playwright will run against real Rails and Ember services and cover the new
topic-list entry, first-visit setup, results header and local-topic action,
location-settings disclosure, invite copying, and the mobile viewport. Existing
privacy, GPS, map, removal, and analytics scenarios remain green.
