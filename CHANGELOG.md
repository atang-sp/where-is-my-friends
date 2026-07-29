# Changelog

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
