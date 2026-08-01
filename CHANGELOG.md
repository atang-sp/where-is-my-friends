# Changelog

## 1.10.0 — 2026-08-01

- Add five fixed Spanking Art Wiki excerpts about safewords, spanko community,
  the history of *Janus*, BDSM terminology, and adult spanking clubs.
- Fetch immutable Internet Archive snapshots because the original site blocks
  automated access, and fail closed if the page ID, revision ID, or page-level
  GFDL notice differs from the reviewed source.
- Remove images, navigation, contact details, exact addresses, unselected
  sections, and paragraphs involving minors, ageplay, non-consent, pornography,
  or explicit sex before any model call.
- Publish each translation as a GFDL 1.3 Modified Version with a distinct title,
  original contributors and history, source and archive locations, modification
  history and copyright notice, publisher details, and the complete unaltered
  GFDL 1.3 text embedded in the topic.
- Limit new publication candidates to the five reviewed Spanking Art entries;
  legacy Wikimedia and Stack Exchange clients remain available only to verify
  records imported by earlier releases.

## 1.9.0 — 2026-08-01

- Add curated CC BY-SA 4.0 Wikipedia excerpts for adult consensual aftercare,
  erotic spanking, discipline, and implement-related education, with live
  site-license verification and permanent revision attribution.
- Keep explicit minors, unclear consent, coercion, explicit erotic stories,
  injury or medical instructions, and other existing hard-risk families out of
  the import pipeline while allowing adult educational BDSM material.
- Format articles separately from Q&A, namespace source identities across
  providers, and synchronize or halt incidents against the exact source type.
- Publish to an administrator-selected public category and add the `sp知识` tag
  to approved spanking, discipline, aftercare, and tools themes.
- Add an idempotent operator task that promotes one validated preview without
  bypassing live source and license revalidation, source identity, record
  state, category checks, theme rotation, or the publication interval.

## 1.8.2 — 2026-08-01

- Retry transient model-gateway failures up to three attempts, honoring short
  `Retry-After` delays for rate limits and using bounded exponential delays for
  HTTP 408, HTTP 5xx, timeouts, and connection failures.
- Continue to fail immediately for authentication, request-shape, endpoint
  policy, and other permanent errors.

## 1.8.1 — 2026-08-01

- Run licensed imports with one administrator-managed model gateway instead of
  requiring a separate OpenAI Moderation profile.
- Retain deterministic content rules, model scope and safety classification,
  strict translation validation, and the independent fidelity review.
- Simplify the provider page to the single configuration the pipeline uses.

## 1.8.0 — 2026-08-01

- Add an administrator AI-provider page for generation and moderation
  credentials, connection tests, and explicit activation without redeploying.
- Support strict structured output through either the Responses API or an
  OpenAI-compatible Chat Completions endpoint with configurable Base URL and
  model.
- Keep OpenAI moderation on a separate fixed official endpoint while allowing
  its credential to be rotated from the same administrator page.
- Store API keys in the plugin database like Discourse AI secrets, while masking
  them from every API response, filtering credential parameters from logs, and
  rejecting non-HTTPS or non-public endpoints.
- Remove legacy provider-key environment fallbacks. Configuration changes pause
  imports and require a fresh successful test before activation; failures never
  trigger automatic provider fallback.

## 1.7.0 — 2026-07-31

- Add a fail-closed, licensed English Q&A translation pipeline using the Stack
  Exchange API, DeepSeek V4 Flash for structured generation, and free OpenAI
  moderation, with deterministic preprocessing and an independent fidelity
  review. Administrators can switch generation back to GPT-5.6 Terra without
  redeploying.
- Add safe-by-default dry-run previews, daily scheduling, theme rotation,
  monthly token limits, source revision monitoring, attribution, duplicate and
  retry protection, and administrator notifications.
- Keep automated posts out of human contribution metrics and cap translated
  topics at two of the five discussion recommendations.
- Pause automatically after three previews await review, seven mature posts
  receive no human reply, or the 30-day reply/original-content gates fail.
- Add an emergency halt task that disables imports and hides affected topics
  after copyright, serious safety, or attribution incidents.

## 1.6.0 — 2026-07-31

- Expand the interest catalogue from 56 to 84 curated tags with finer SP
  psychology, scene, position, tool, aftercare, and practice-intent groups.
- Add per-group selection modes: single-select for intensity, role, and
  practice frequency; multi-select with per-group caps for the remaining
  groups.
- Raise the global interest selection limit from 12 to 20 and validate
  per-group limits on both client and server.
- Seed the expanded Discourse tags for existing sites via migration.

## 1.5.1 — 2026-07-31

- Fix join-notification checkbox layout: setup input styles no longer leak into
  the notification fieldset, restoring horizontal label alignment.

## 1.5.0 — 2026-07-30

- Add a response-first member lobby that highlights privacy-respecting online
  members and recently active contributors, with direct chat or message
  actions.
- Expand city discovery into a regional network with active and growing city
  directories, radius previews, city groups, and automatic bounded radius
  expansion.
- Add public local-topic recommendations and creation links without exposing
  precise coordinates or unreadable discussions.
- Replace the monthly nearby-member digest with an independent weekly nearby
  notification preference and route those notifications back to Local Friends.
- Add city-join timestamps, nearby notification preferences, regional
  engagement metrics, responsive layouts, and request, job, QUnit, and
  Playwright coverage.
- Preserve the v1.4 community discovery, interest recommendation, and practice
  invitation experiences while integrating the regional and activity-focused
  discovery flow.

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
