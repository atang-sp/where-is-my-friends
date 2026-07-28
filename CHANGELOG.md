# Changelog

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
