# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Discourse plugin that allows users to discover nearby friends while protecting privacy. It supports both real GPS-based location sharing (with ±500m noise added) and virtual location selection via maps.

## Development Commands

```bash
# Run database migrations (from Discourse root)
bundle exec rake db:migrate

# Lint files
bin/lint plugins/where-is-my-friends/path/to/file

# Run plugin tests (if any exist)
bin/rspec plugins/where-is-my-friends/spec/
```

## Architecture

### Backend (Ruby)

- **plugin.rb**: Main entry point - registers assets, loads models/controllers, defines routes
- **app/controllers/where_is_my_friends/locations_controller.rb**: API controller handling location CRUD and nearby search
- **app/models/user_location.rb**: ActiveRecord model with Haversine distance calculations
- **app/serializers/user_location_serializer.rb**: JSON serialization for user locations
- **config/settings.yml**: Plugin site settings (distance limits, map provider, API keys)

### Frontend (Ember.js)

- **assets/javascripts/discourse/controllers/where-is-my-friends.js**: Main controller with location sharing logic
- **assets/javascripts/discourse/templates/where-is-my-friends.hbs**: Main page template
- **assets/javascripts/discourse/components/virtual-location-picker.js**: Map-based location picker
- **assets/javascripts/discourse/lib/where-is-my-friends-geolocation.js**: Browser geolocation wrapper
- **assets/javascripts/discourse/lib/where-is-my-friends-maps.js**: Multi-provider map abstraction (Amap, Baidu, OpenStreetMap)

### API Routes

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/where-is-my-friends` | Get current user's location data |
| POST | `/api/where-is-my-friends/locations` | Create/update user location |
| GET | `/api/where-is-my-friends/locations/nearby` | Find nearby users |
| DELETE | `/api/where-is-my-friends/locations` | Remove user's location |
| GET | `/api/where-is-my-friends/ip-location` | Get location from IP (fallback) |

### Key Site Settings

- `where_is_my_friends_enabled`: Enable/disable plugin
- `where_is_my_friends_default_distance_km`: Default search radius
- `where_is_my_friends_max_users_display`: Maximum nearby users to show
- `where_is_my_friends_enable_virtual_location`: Allow virtual location selection
- `where_is_my_friends_map_provider`: Map service (amap/baidu/openstreetmap)

## Privacy Model

- Real locations have ±500m random noise added via `UserLocation.upsert_location`
- Locations track source (`gps`, `ip`, `virtual`, `unknown`) and accuracy
- Virtual locations are stored exactly as selected by user (no noise)
- `is_virtual` and `location_type` fields distinguish location types

## Internationalization

- Client strings: `config/locales/client.en.yml`, `config/locales/client.zh_CN.yml`
- Server strings: `config/locales/server.en.yml`, `config/locales/server.zh_CN.yml`

All user-facing strings should be translatable using I18n (Ruby) or the i18n service (JS).

## Follows Parent Discourse CLAUDE.md

This plugin follows all conventions from the parent Discourse `CLAUDE.md`:
- Always lint changed files
- Use `fab!()` over `let()` in specs
- Access settings via `SiteSetting.name` (Ruby) or `siteSettings.name` (JS)
