# Rich interest catalogue design

## Why this exists

The first interest onboarding release derived its choices from tags on recent
visible topics. That was permission-safe, but a small or inconsistently tagged
forum produced a shallow interest page. The catalogue is now plugin-owned and
uses forum tags only as storage and topic associations.

The taxonomy was informed by the public
[“SP 喜好瓶”](https://freesp446798036.wordpress.com/category/sp%E5%96%9C%E5%A5%BD%E7%93%B6/)
pattern of separating a preference into dimensions such as interaction type,
intensity, role, experience, additions, tools, focus, and posture. The plugin
does not copy that worksheet. It adapts the dimensional idea into neutral
community-discovery groups and adds content, communication, consent, boundary,
and aftercare interests.

## Source of truth

`config/interest_catalogue.yml` is the catalogue and relationship source of
truth. Each entry has:

- a stable key and a Chinese tag name;
- a group used by the searchable onboarding UI;
- related keys used for lower-weight member similarity;
- optional legacy topic-tag aliases;
- optional public topic-title keywords.

The data migration inserts the tag rows on existing sites. The matching plugin
fixture inserts the same rows on fresh installs. Administrators can supplement
the built-in catalogue with up to 20 forum tags through
`where_is_my_friends_interest_tags`. A member's previously selected legacy tag
is kept in their own editing catalogue so an upgrade never silently deletes a
choice.

## Recommendation rules

- Member similarity scores exact tag names highest, canonical/legacy aliases
  next, and related catalogue entries lower.
- Completed profiles must explicitly remain recommendable. Profile visibility,
  activity, suspension, silence, mute, and ignore rules still apply.
- A member can be recommended from profile similarity without having posted.
  If visible public contributions exist, those remain the preferred
  explanation and representative topics.
- The response never serializes the candidate's purpose or private selection
  list. Similarity explanations contain only the viewer's selected interests.
- Topic candidates come only from `TopicQuery` for the viewer. Exact tags,
  legacy aliases, and title keywords are scored; private or muted content is
  never widened into the pool.
- Related interests are discovery signals only. A practice invitation still
  requires an exact common tag and all existing consent and communication
  gates.

## Maintenance

When adding an interest, update the YAML catalogue and both provisioning paths:
the fixture reads the YAML automatically, while the historical migration must
remain immutable. A future addition therefore needs a new generated migration
for existing sites. Keep relationships narrowly meaningful and avoid treating
a match as consent.
