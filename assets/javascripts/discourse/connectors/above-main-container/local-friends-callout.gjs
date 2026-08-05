import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action, get } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import {
  HOMEPAGE_DISCOVERY_ENTRIES,
  homepageDiscoveryEntry,
} from "discourse/plugins/where-is-my-friends/discourse/lib/homepage-discovery-entry";
import { isWhereIsMyFriendsTargetCategory } from "discourse/plugins/where-is-my-friends/discourse/lib/target-category";

const STORAGE_KEY = "local-friends-callout-state";
const MAX_VIEWS = 2;
const DISMISS_DAYS = 7;

function readCalloutState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return { views: 0, cooldownUntil: null, open: false };
    }
    const parsed = JSON.parse(raw);
    return {
      views: Number(parsed.views) || 0,
      cooldownUntil: parsed.cooldownUntil || null,
      open: Boolean(parsed.open),
    };
  } catch {
    return { views: 0, cooldownUntil: null, open: false };
  }
}

function writeCalloutState(state) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    // Storage may be unavailable; tracked state still controls this page.
  }
}

function shouldCompact(state) {
  return state.views >= MAX_VIEWS;
}

export default class LocalFriendsCallout extends Component {
  @service currentUser;
  @service router;
  @service siteSettings;

  @tracked data = null;
  @tracked city = "";
  @tracked saving = false;
  @tracked hasSuggestion = false;
  @tracked error = null;
  @tracked justJoined = false;
  @tracked dismissed = false;
  @tracked compact = false;
  calloutState = readCalloutState();
  recordedImpressionSurfaces = new Set();

  constructor() {
    super(...arguments);
    this.compact = shouldCompact(this.calloutState);
  }

  get shouldLoad() {
    return Boolean(
      this.currentUser &&
      this.isTopicListRoute &&
      (!this.isHomeRoute ||
        this.homepageEntry === HOMEPAGE_DISCOVERY_ENTRIES.LOCAL) &&
      !this.calloutCooldownActive
    );
  }

  get homepageEntry() {
    return homepageDiscoveryEntry({
      onboardingState: get(
        this.currentUser,
        "where_is_my_friends_interest_onboarding_state"
      ),
      enabled:
        this.siteSettings.where_is_my_friends_interest_onboarding_enabled,
    });
  }

  get calloutCooldownActive() {
    const persistedState = readCalloutState();
    const cooldownTimestamp = Date.parse(
      persistedState.cooldownUntil ?? this.calloutState.cooldownUntil ?? ""
    );
    return Number.isFinite(cooldownTimestamp) && cooldownTimestamp > Date.now();
  }

  get isHomeRoute() {
    const routeName = this.router.currentRouteName ?? "";
    return (
      !this.isCategoryRoute &&
      (routeName === "discovery" || routeName.startsWith("discovery."))
    );
  }

  get isCategoryRoute() {
    const routeName = this.router.currentRouteName ?? "";
    return Boolean(
      routeName === "discovery.categories" ||
      routeName.startsWith("category.") ||
      this.router.currentRoute?.attributes?.category
    );
  }

  get isTopicListRoute() {
    return this.isHomeRoute || this.isCategoryRoute;
  }

  get isTargetCategory() {
    if (!this.isCategoryRoute) {
      return false;
    }
    return isWhereIsMyFriendsTargetCategory(
      this.router.currentRoute?.attributes?.category,
      this.siteSettings
    );
  }

  get calloutSurface() {
    if (this.isHomeRoute) {
      return "homepage";
    }

    if (this.isCategoryRoute) {
      return "category";
    }

    return null;
  }

  get isCategoryMode() {
    return this.isTargetCategory && !this.hasLocation;
  }

  get hasLocation() {
    return Boolean(this.data?.location) || this.justJoined;
  }

  get newMemberCount() {
    return this.data?.new_nearby_count ?? 0;
  }

  get returningWidgetText() {
    const count = this.newMemberCount;
    if (count > 0) {
      return i18n("where_is_my_friends.sidebar_widget_new_members", { count });
    }
    return i18n("where_is_my_friends.sidebar_widget_no_new");
  }

  get proof() {
    const participants = this.data?.active_participants;
    if (!participants || participants.suppressed) {
      return i18n("where_is_my_friends.callout_proof_generic");
    }

    return i18n("where_is_my_friends.callout_proof_count", {
      count: participants.count,
    });
  }

  get calloutCities() {
    const directory = this.data?.city_directory;
    const seen = new Set();
    return [...(directory?.active ?? []), ...(directory?.growing ?? [])]
      .filter((entry) => {
        const key = entry.city_key ?? entry.city;
        if (seen.has(key)) {
          return false;
        }
        seen.add(key);
        return true;
      })
      .slice(0, 4)
      .map((entry) => ({
        ...entry,
        url: `/where-is-my-friends?auto_city=${encodeURIComponent(entry.city)}`,
      }));
  }

  get categoryProof() {
    const participants = this.data?.active_participants;
    if (!participants || participants.suppressed) {
      return null;
    }

    return i18n("where_is_my_friends.category_callout_description", {
      count: participants.count,
      city_count: participants.city_count ?? 1,
    });
  }

  get joinedCity() {
    return this.data?.location?.city || this.city.trim();
  }

  @action
  async load() {
    if (this.data) {
      return;
    }

    try {
      this.data = await ajax("/where-is-my-friends.json");
      if (!this.data.location && this.data.profile_location) {
        this.city = this.data.profile_location;
        this.hasSuggestion = true;
      }
    } catch {
      // The optional entry must never block topic-list rendering.
    }
  }

  @action
  recordCalloutImpression() {
    const surface = this.calloutSurface;
    if (!surface || this.recordedImpressionSurfaces.has(surface)) {
      return;
    }

    this.recordedImpressionSurfaces.add(surface);
    void this.recordEvent("local_callout_viewed");
    this.recordView();
  }

  recordView() {
    if (this.calloutState.open) {
      return;
    }

    this.calloutState = {
      views: this.calloutState.views + 1,
      cooldownUntil: null,
      open: true,
    };
    writeCalloutState(this.calloutState);
    this.compact = shouldCompact(this.calloutState);
  }

  @action
  updateCity(event) {
    this.city = event.target.value;
    this.error = null;
  }

  @action
  async saveCity(event) {
    event?.preventDefault?.();

    const city = this.city.trim();
    if (!city || this.saving) {
      return;
    }

    this.saving = true;
    this.error = null;

    try {
      const response = await ajax("/where-is-my-friends/locations.json", {
        type: "POST",
        data: { city, discovery_mode: "city" },
      });
      this.data = {
        ...this.data,
        location: response.location,
        state: response.state,
      };
      this.justJoined = true;
      void this.recordEvent("local_callout_location_saved");
    } catch {
      this.error = i18n("where_is_my_friends.callout_save_error");
    } finally {
      this.saving = false;
    }
  }

  @action
  dismiss() {
    void this.recordEvent("local_callout_dismissed");
    const views = Math.max(this.calloutState.views, MAX_VIEWS);
    this.calloutState = {
      views,
      open: false,
      cooldownUntil: this.hasLocation
        ? new Date(
            Date.now() + DISMISS_DAYS * 24 * 60 * 60 * 1000
          ).toISOString()
        : null,
    };
    writeCalloutState(this.calloutState);

    if (this.hasLocation) {
      this.dismissed = true;
    } else {
      this.compact = true;
    }
  }

  @action
  trackOpen() {
    void this.recordEvent("local_callout_opened");
  }

  async recordEvent(eventName) {
    try {
      await ajax("/where-is-my-friends/events.json", {
        type: "POST",
        data: {
          event_name: eventName,
          surface: this.calloutSurface,
        },
      });
    } catch {
      // Measurement must never block local discovery.
    }
  }

  <template>
    {{#if this.shouldLoad}}
      <span hidden {{didInsert this.load}}></span>
      {{#if this.data}}
        {{#if this.isCategoryMode}}
          <section
            class="local-friends-callout-banner local-friends-callout-banner--category"
            data-test-local-friends-category-callout
            {{didInsert this.recordCalloutImpression}}
            {{didUpdate this.recordCalloutImpression this.calloutSurface}}
          >
            <div class="local-friends-callout-banner__content">
              <strong>{{i18n
                  "where_is_my_friends.category_callout_title"
                }}</strong>
              {{#if this.categoryProof}}
                <p>{{this.categoryProof}}</p>
              {{/if}}
              {{#if this.error}}
                <p
                  class="local-friends-callout-banner__error"
                  data-test-callout-error
                >{{this.error}}</p>
              {{/if}}
            </div>
            <form
              class="local-friends-callout-banner__setup"
              data-test-local-friends-callout-setup
              {{on "submit" this.saveCity}}
            >
              <input
                type="text"
                value={{this.city}}
                placeholder={{i18n
                  "where_is_my_friends.callout_city_placeholder"
                }}
                autocomplete="address-level2"
                aria-label={{i18n "where_is_my_friends.city"}}
                data-test-callout-city-input
                {{on "input" this.updateCity}}
              />
              <DButton
                @action={{this.saveCity}}
                @label="where_is_my_friends.category_callout_cta"
                @icon="location-dot"
                @disabled={{this.saving}}
                class="btn-primary"
                data-test-callout-save-city
              />
            </form>
          </section>
        {{else if this.hasLocation}}
          {{#unless this.dismissed}}
            <section
              class="local-friends-callout-banner local-friends-callout-banner--returning"
              data-test-local-friends-callout
              data-test-local-friends-returning
              {{didInsert this.recordCalloutImpression}}
              {{didUpdate this.recordCalloutImpression this.calloutSurface}}
            >
              <div class="local-friends-callout-banner__content">
                <strong>{{this.returningWidgetText}}</strong>
              </div>
              <LinkTo
                @route="where-is-my-friends"
                class="btn btn-primary btn-small"
                data-test-local-friends-callout-cta
                {{on "click" this.trackOpen}}
              >
                {{i18n "where_is_my_friends.sidebar_widget_view"}}
              </LinkTo>
              <DButton
                @action={{this.dismiss}}
                @icon="xmark"
                @ariaLabel="where_is_my_friends.callout_dismiss"
                @title="where_is_my_friends.callout_dismiss"
                class="btn-flat no-text local-friends-callout-banner__dismiss"
                data-test-dismiss-local-friends
              />
            </section>
          {{/unless}}
        {{else}}
          {{#unless this.dismissed}}
            {{#if this.compact}}
              <section
                class="local-friends-callout-banner local-friends-callout-banner--compact"
                data-test-local-friends-callout
                {{didInsert this.recordCalloutImpression}}
                {{didUpdate this.recordCalloutImpression this.calloutSurface}}
              >
                <div class="local-friends-callout-banner__content">
                  <strong>{{i18n "where_is_my_friends.callout_title"}}</strong>
                </div>
                <LinkTo
                  @route="where-is-my-friends"
                  class="btn btn-primary btn-small"
                  data-test-local-friends-callout-cta
                  {{on "click" this.trackOpen}}
                >
                  {{i18n "where_is_my_friends.callout_set_city"}}
                </LinkTo>
              </section>
            {{else}}
              <section
                class="local-friends-callout-banner"
                data-test-local-friends-callout
                {{didInsert this.recordCalloutImpression}}
                {{didUpdate this.recordCalloutImpression this.calloutSurface}}
              >
                <div class="local-friends-callout-banner__content">
                  {{#if this.justJoined}}
                    <strong>{{i18n
                        "where_is_my_friends.callout_joined_title"
                      }}</strong>
                    <p>{{i18n
                        "where_is_my_friends.callout_joined_description"
                        city=this.joinedCity
                      }}</p>
                  {{else}}
                    <strong>{{i18n
                        "where_is_my_friends.callout_title"
                      }}</strong>
                    <p>{{#if this.hasSuggestion}}
                        {{i18n
                          "where_is_my_friends.callout_suggestion"
                          city=this.city
                        }}
                      {{else}}
                        {{i18n "where_is_my_friends.callout_setup_description"}}
                      {{/if}}</p>
                    <span
                      data-test-local-friends-callout-proof
                    >{{this.proof}}</span>
                    {{#if this.calloutCities.length}}
                      <div class="where-is-my-friends__city-grid">
                        {{#each this.calloutCities as |entry|}}
                          <a
                            class="where-is-my-friends__city-card"
                            href={{entry.url}}
                            data-test-callout-city-card={{entry.city_key}}
                            {{on "click" this.trackOpen}}
                          >
                            <strong>{{entry.city}}</strong>
                            <span>{{i18n
                                "where_is_my_friends.city_directory_counts"
                                active=entry.recent_active_count
                                joined=entry.joined_count
                              }}</span>
                          </a>
                        {{/each}}
                      </div>
                    {{/if}}
                  {{/if}}
                  {{#if this.error}}
                    <p
                      class="local-friends-callout-banner__error"
                      data-test-callout-error
                    >
                      {{this.error}}
                    </p>
                  {{/if}}
                </div>

                {{#unless this.calloutCities.length}}
                  <form
                    class="local-friends-callout-banner__setup"
                    data-test-local-friends-callout-setup
                    {{on "submit" this.saveCity}}
                  >
                    <input
                      type="text"
                      value={{this.city}}
                      placeholder={{i18n
                        "where_is_my_friends.callout_city_placeholder"
                      }}
                      autocomplete="address-level2"
                      aria-label={{i18n "where_is_my_friends.city"}}
                      data-test-callout-city-input
                      {{on "input" this.updateCity}}
                    />
                    <DButton
                      @action={{this.saveCity}}
                      @label="where_is_my_friends.callout_save_city"
                      @icon="location-dot"
                      @disabled={{this.saving}}
                      class="btn-primary"
                      data-test-callout-save-city
                    />
                  </form>
                {{/unless}}

                <DButton
                  @action={{this.dismiss}}
                  @icon="xmark"
                  @ariaLabel="where_is_my_friends.callout_dismiss"
                  @title="where_is_my_friends.callout_dismiss"
                  class="btn-flat no-text local-friends-callout-banner__dismiss"
                  data-test-dismiss-local-friends
                />
              </section>
            {{/if}}
          {{/unless}}
        {{/if}}
      {{/if}}
    {{/if}}
  </template>
}
