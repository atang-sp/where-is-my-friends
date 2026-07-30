# Changelog

## 1.4.0 — 2026-07-30

- Add a persistent homepage Community Discovery panel with three discussions,
  three members, and two interest entrances, plus refresh and per-card
  dismissal controls.
- Rank discussions for participation using explicit interest, recent behavior,
  reply opportunity, freshness, relationship bridge, new-member, and
  exploration signals; penalize already-read/replied, stale, and
  same-author-concentrated results.
- Reserve the five-topic mix for three high-relevance results, a fresh
  discussion awaiting a response, and an adjacent-interest exploration when
  eligible candidates exist.
- Rotate bounded top-ranked candidate pools on refresh and penalize discussions
  with substantial prior reading time without storing target-level exposure
  history.
- Explain the immediate action on every card and link adjacent exploration
  back to the selected interest that caused it.
- Suppress exact active-member counts on interest entrances below the existing
  aggregate privacy threshold.
- Record target-free recommendation impressions and actions by surface,
  candidate source, rank bucket, algorithm version, and result bucket on both
  the homepage and interest page.
- Add aggregate impression-to-open, topic-open-to-24-hour-reply,
  member-to-related-topic, member-to-invite, impression-to-24-hour-reply, and
  seven-day public interaction rates, with the latter as the recommendation
  north-star metric.

## 1.3.0 — 2026-07-29

- Replace the recent-topic-derived interest list with a plugin-owned catalogue
  of 56 grouped SP interests.
- Add catalogue search and raise the selection range from 3–5 to 3–12.
- Recommend opted-in members from exact, aliased, and related private
  selections even when they have not posted in a matching topic.
- Map curated interests to viewer-visible public topics through exact tags,
  legacy tag aliases, and title keywords.
- Preserve each member's legacy selections and support up to 20
  administrator-supplied supplemental tags.
- Keep related-interest discovery separate from practice consent: invitations
  still require an exact shared tag and all existing safety gates.

## 1.2.0 — 2026-07-28

- Add strictly one-to-one practice invitations from recommendations and public-interest profiles.
- Require a currently verifiable shared interest and enforce trust-level, daily-limit, PM-permission, ignore/mute, duplicate-pending, and recipient opt-out gates.
- Let recipients accept, decline, or ignore; accepting creates a PM containing exactly the sender and recipient.
- Add optional proposed time, optional 500-character note, localized preset copy, actionable notifications, inbox, sent history, and notification preference.
- Interpret proposed times in the sender's browser timezone and store the resulting UTC instant.
- Respect Discourse PM allowlists, recheck communication safety on acceptance, and preserve an immutable interest-name snapshot if a tag is later deleted.
- Import the last 90 days of legacy practice intents as private bookmarks requiring explicit reconfirmation without sending invites.
- Preserve every legacy mutual pair as notification-suppressed history, including pairs older than 90 days.

## 1.1.0 — 2026-07-26

- Add skippable interest onboarding for new and existing members.
- Recommend up to five visible topics and three opted-in, recently active contributors.
- Explain every recommendation using visible tags and public representative topics.
- Add private-by-default interests, optional profile display, opt-out, dismissal, editing, and full data clearing.
- Respect current tag permissions, hidden posts, muted categories/tags, and ignore/mute relationships in both directions.
- Add aggregate, privacy-safe onboarding, recommendation-open, seven-day public-interaction, and first-reply metrics.
- Handle catalogue changes safely during editing and provide explicit loading, error, empty, and disabled states.
