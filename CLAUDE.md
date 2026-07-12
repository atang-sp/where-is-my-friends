# Repository guidance

This is a city-first local discovery plugin for current Discourse.

## Product invariants

- City mode is the default and must work without coordinates or geolocation permission.
- GPS and map are optional enhancements; both still require a city.
- Discovery uses only the signed-in user's server-side record. Never accept search-origin coordinates from the client.
- Never serialize or log coordinates, exact distances, or exception backtraces.
- Never serialize custom user fields unless explicitly whitelisted via `where_is_my_friends_filterable_user_fields`. Only admin-curated dropdown fields are allowed.
- Results exclude the current user and expired/disabled records.
- Analytics accepts only the event/model allowlists and contains no location values.
- Keep explicit setup, ready, empty, loading, expired, and error states.

## Architecture

- Rails engine API: `app/controllers/where_is_my_friends/`
- Domain model: `app/models/user_location.rb`
- Native Glimmer UI: `assets/javascripts/discourse/components/*.gjs`
- Server tests: `spec/`
- QUnit tests: `test/javascripts/`
- Real-browser tests: `e2e/`

## Commands

Run from the parent Discourse checkout:

```bash
d/rake 'plugin:spec[where-is-my-friends]'
CI=1 d/rake 'plugin:qunit[where-is-my-friends]'
d/exec bin/lint plugins/where-is-my-friends
```

Use `fab!` in specs, current GJS/native classes in the frontend, Discourse UI-kit components for dialogs/buttons, and translation keys for all user-facing text.
