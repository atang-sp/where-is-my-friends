# City-first local discovery design

## Objective

Turn the plugin from a GPS-gated nearby-user list into a low-friction local
community directory. City and region are the default discovery boundary. GPS
and map locations remain optional and only improve coarse distance bands.

The feature must create a complete loop: discover local people, understand why
they are relevant, contact them or find local discussions, and have a reason to
return. It must also make adoption measurable without collecting raw location
analytics.

## Product decisions

1. Every active location has a user-entered city and an optional region.
2. First-time setup asks only for city and region. It does not request browser
   location permission or load a map.
3. Users may opt into an advanced mode:
   - GPS mode obtains a browser location.
   - Map mode lets the user choose an approximate point.
4. Precise coordinates never leave the location-write request and are never
   returned by the API. The client cannot supply a search origin.
5. Results are matched by a normalized city key. If both users opted into a
   precise mode, the server returns a distance band, never an exact distance.
6. The user's own record is excluded. Expired records are excluded and removed
   automatically.
7. A result card offers three meaningful next actions: view profile, start a
   private message, and search for topics mentioning the city.
8. Advanced filters are secondary and are hidden when too few results exist.

## User experience

### First visit

The page opens with a short value statement and an aggregate count of recently
active participants. The count has a privacy threshold; small counts are shown
as a generic message rather than an exact number.

The primary form contains city and optional region fields. Existing active city
names are suggested, but free text is permitted. Submission immediately saves
the preference and loads local results. A compact disclosure explains that the
default mode stores no coordinates.

### Returning visit

The route automatically loads results for an active saved location. There is no
separate Find button. The page shows when the user's location expires and lets
the user update or remove it.

### Empty and error states

An empty result is a first-class state rather than a hidden array. It offers a
local-topic search and a share/invite suggestion. Network, validation, map, and
permission failures are plain translated text and always leave city mode
available. Raw HTML error rendering is removed.

### Advanced location

Advanced location is an explicit optional section. GPS and map modes still
require a city so matching remains stable when only one user has coordinates.
The map defaults to OpenStreetMap with locally served Leaflet assets; Amap and
Baidu remain configurable browser SDKs. Browser keys are documented as public,
domain-restricted keys. Reverse geocoding is not required and coordinates are
not sent to an unrelated geocoder.

## Data model

`user_locations` gains:

- `city`: display label entered by the user.
- `city_key`: normalized comparison key.
- `region`: optional display label.
- `discovery_mode`: `city`, `gps`, or `map`.
- `expires_at`: hard visibility and retention deadline.

Latitude and longitude become nullable for city mode. Existing records migrate
to `gps` or `map` mode based on their legacy source but remain undiscoverable
until a city is supplied. This avoids guessing a city from stored coordinates.

City normalization trims whitespace, collapses repeated spaces, lowercases
Latin text, and removes a small set of administrative suffixes used by the
Chinese UI. Display labels are preserved.

Location expiry defaults to 30 days and is configurable. A scheduled job deletes
expired records, while every read also filters them so correctness does not
depend on the job schedule. Removing a location destroys the row immediately.

`where_is_my_friends_events` stores allowlisted funnel events:

- `page_view`
- `setup_started`
- `location_saved`
- `results_viewed`
- `profile_clicked`
- `message_started`
- `local_topics_clicked`
- `location_removed`

Rows contain user ID, event name, location mode, a coarse result-count bucket,
and timestamp. They never contain coordinates, city, region, address, query
text, IP address, or browser details. A daily job removes events older than 90
days.

## Server API and privacy boundary

The mounted engine is the single routing authority. Duplicate application routes
and the unused ERB view are removed.

- `GET /where-is-my-friends.json` returns current location metadata without
  coordinates, settings needed by the client, active aggregate participation,
  and city suggestions.
- `POST /where-is-my-friends/locations` validates and saves city mode or an
  explicitly selected advanced mode.
- `GET /where-is-my-friends/locations/nearby` uses only the authenticated user's
  stored active location. It accepts filters but no latitude or longitude.
- `DELETE /where-is-my-friends/locations` destroys the authenticated user's
  location.
- `POST /where-is-my-friends/events` records an allowlisted event.
- `GET /where-is-my-friends/debug-stats` remains admin-only and reports aggregate
  funnel and freshness data without coordinates.

All responses expose an explicit result state (`ready`, `empty`, `setup`, or
`expired`) so the UI never infers state from array truthiness. User fields are
selected by configured field IDs and Discourse visibility rules; arbitrary
custom fields are never serialized.

Queries clamp result limits to 200, filter by normalized city and expiry in SQL,
exclude the current user, and order by recent activity. Precise-mode results
calculate distance server-side and map it into configurable bands such as
`under_5`, `5_to_20`, and `over_20`.

## Front-end architecture

Legacy classic Ember objects and `.hbs` templates are replaced with native
classes and `.gjs` components compatible with current Discourse. Standard
Discourse buttons, links, icons, modal/dialog behavior, and translated strings
replace hand-built overlays, raw anchors, Font Awesome markup, and raw HTML error
messages.

The route owns initial data loading. A page component owns setup state, filters,
automatic result loading, analytics events, and actions. The optional map picker
is isolated and lazy-loaded so the default city experience has no map cost or
CSP dependency.

## Observability and adoption metrics

The admin stats endpoint reports, for selectable time windows:

- unique page visitors
- setup completion rate
- percentage of completed setups that produced at least one other user
- profile and message conversion rates
- seven-day return rate
- result-count bucket distribution
- active and expired location totals by mode

The UI emits events only after the corresponding user-visible state or action
occurs. Failed requests are not counted as successes.

## Testing strategy

Server request and model tests cover authorization, city normalization, expiry,
destructive removal, coordinate confidentiality, field allowlisting, aggregate
privacy thresholds, event allowlisting, retention, result limits, and distance
bands.

Front-end tests cover first-time city setup, returning-user automatic loading,
empty results, filtering, safe errors, advanced-mode fallbacks, and action-event
emission. Accessibility checks cover dialog focus, labels, keyboard use, and
mobile layout.

Playwright runs against a real Discourse development instance with the plugin
installed. It exercises two users in the same city plus an administrator:

1. city-only onboarding and automatic results
2. empty city state
3. profile, private-message, and topic-search actions
4. GPS denial followed by successful city-mode fallback
5. map selection
6. location removal
7. mobile viewport
8. admin aggregate funnel report

No merge to `main` occurs until server tests, front-end tests, linting, and the
Playwright suite all pass on the feature branch.

