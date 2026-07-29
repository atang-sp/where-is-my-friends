# Practice Invitations 1.2.0 Rollout

## Deployment order

1. Take a PostgreSQL backup that includes `practice_interests`, `notifications`, and all `where_is_my_friends_*` tables.
2. Deploy `where-is-my-friends` 1.2.0 and `discourse-plugin-matching` 1.0.2 in the same Discourse rebuild.
3. Run all migrations and post-migrations before accepting traffic.
4. Keep `discourse-plugin-matching` installed for one full release cycle. Its page and API are read-only and point to `/where-is-my-friends/interests`.
5. Remove the old plugin from production `app.yml` only after the observation gates below pass. Keep the database backup until the rollback window closes.

## Migration invariants

- `practice_interests` rows from the previous 90 days become private `needs_reconfirmation` bookmarks.
- Reciprocal legacy rows become one ordered pair-history row with `notification_suppressed = TRUE`, regardless of age.
- Re-running the importer is safe and does not reset a bookmark already reconfirmed or dismissed.
- Importing or reconfirming never inserts a practice invitation, PM, or notification.

## Production verification

```sql
SELECT COUNT(*) FROM where_is_my_friends_legacy_practice_bookmarks;
SELECT COUNT(*) FROM where_is_my_friends_legacy_practice_pairs;
SELECT COUNT(*) FROM where_is_my_friends_legacy_practice_pairs
WHERE notification_suppressed IS NOT TRUE;
SELECT COUNT(*) FROM where_is_my_friends_practice_invitations;
```

Verify with two non-staff test members:

1. A recommended member exposes at least one eligible shared interest.
2. Sending creates one pending invitation and one notification, but no PM.
3. Decline and ignore create no PM.
4. Accept creates one PM whose allowed-user set contains exactly the two members.
5. Muting either direction or disabling the invitation preference prevents a new invite.
6. The legacy page shows history, has no add/remove controls, and links to Local Friends.

## Observation gates before old-plugin removal

- One release cycle completes without migration, privacy, notification, or PM-participant regressions.
- Imported bookmark and pair counts match the pre-deploy audit; the known production mutual-pair count is five.
- No legacy add/remove request succeeds after deployment.
- A fresh backup exists and the rollback procedure has been exercised or reviewed.

Removing the old plugin code does not authorize dropping `practice_interests`. Retain the table and backup until the rollback window is explicitly closed.

## 1.2.1 observation restart

Production verification on 2026-07-29 found that the profile invitation link
lost its `invite_to` query parameter before the invitation component read it, so
the availability request was never made and the form did not open. Version
1.2.1 declares the route query parameter and passes it explicitly to the
component. Restart the full release-cycle observation window when 1.2.1 is
deployed.

For this rollout, one full release cycle means at least 24 continuous hours on
the same 1.2.1 production build without a container restart. The current window
started at `2026-07-29T11:47:57Z` (`2026-07-29 19:47:57 +08:00`), so the
old-plugin removal gate cannot open before `2026-07-30T11:47:57Z`
(`2026-07-30 19:47:57 +08:00`). Any new invitation regression, migration
regression, privacy leak, notification error, invalid PM participant set, or
production rebuild restarts the window.

At the end of the window, repeat the production verification queries, confirm
that the running commit is still the 1.2.1 release commit, confirm there are no
plugin-related error log entries, and take a new backup before editing
`app.yml`.
