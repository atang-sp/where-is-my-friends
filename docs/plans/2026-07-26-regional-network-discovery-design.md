# Regional network discovery design

## Objective

Increase meaningful local connections by showing the value of the regional
network before a member commits to a city. The product must not reduce local
discovery to a global popularity leaderboard: popular cities provide social
proof, while distance determines relevance after a user previews a city.

The primary success metric is the percentage of members who, within seven days
of joining local discovery, start a message or chat, reply to a local topic, or
interact with a local activity topic. Thirty-day return rate is a supporting
metric.

## Visibility contract

- Every signed-in forum member can browse city names, aggregate counts, and
  local topics before joining local discovery.
- Individual member profiles are unlocked only after the viewer joins with
  their real city.
- Joined members can see individual profiles only inside their selected
  discovery radius. Cities outside that radius remain aggregate-only.
- Exact coordinates and exact member-to-member distances never leave the
  server.

## City directory

Before a city is entered, the page shows two rotating sets:

- recently active cities;
- recently growing cities.

The directory contains only cities with at least one joined member. Search can
preview any canonical city, including a city with no members.

Each city card displays:

- members active on the forum in the last 90 days;
- cumulative joined members.

Counts are exact, including counts of one and two. Small-city copy is factual,
not gamified. Equal-ranked cities rotate deterministically by date so the same
large cities do not permanently monopolize discovery.

City input uses the bundled canonical city catalogue. A value outside the
catalogue can still be joined, but it is marked as unverified and cannot claim
distance-based matches until an administrator maps it to a canonical city.

## No-commitment preview

Selecting a city does not save a location. It opens an inline preview with:

- the city's recent-active and cumulative counts;
- counts for the 50, 100, and 200 kilometre rings;
- nearby cities ordered by distance, then recent-active count;
- local topics tagged with the previewed activity city;
- a recommended radius.

The recommended radius is the smallest supported radius containing at least
three members who were active in the last 90 days. If no radius reaches three,
the preview recommends the radius containing the most active members and states
the real count without manufacturing activity.

The user explicitly confirms their city, radius, and notification preferences
before joining.

## Joined discovery

Results are grouped by city:

1. the member's own city;
2. nearby cities ordered by distance;
3. members inside each city ordered by recent forum activity.

Members inactive for more than 90 days remain visible after active members and
receive a coarse inactive label. Their profiles and message action remain
available, but they do not count toward recommended-radius activity.

The primary community action is a native Discourse local topic. Direct message
or chat remains available on each member card as a secondary one-to-one action.
Every local topic has one canonical activity-city tag; the plugin aggregates
topics whose city is inside the viewer's selected radius.

## Notifications

Joining presents two independent, default-enabled notification choices:

- same-city member joins: immediate native Discourse notification;
- member joins elsewhere inside the selected radius: weekly native Discourse
  digest.

Notifications respect existing Discourse email preferences. They never include
coordinates or exact distances.

## Entry and safety

The complete directory remains in the plugin tab. A dismissible compact preview
on topic-list and discovery routes shows active and growing cities and links to
the directory.

The plugin reuses Discourse ignore, block, report, messaging, chat, topic, and
tag interfaces. It adds concise first-contact and public-meeting safety copy but
does not create a separate trust or reporting system.

## Analytics

Allowlisted aggregate events cover:

- directory viewed;
- city previewed;
- radius confirmed;
- location saved;
- results viewed with a coarse result-count bucket;
- local topic opened or interacted with;
- message or chat started;
- notification opened;
- seven- and thirty-day return.

Events contain no city, region, coordinate, distance, query, username, topic
content, or exception data.

## Delivery

The experience ships as one complete release, guarded by the existing plugin
setting. Request specs cover the network snapshot and privacy contract; QUnit
covers the directory, preview, join, grouping, inactive state, and entry
callout; Playwright covers the same critical path against real Rails and Ember
services.
