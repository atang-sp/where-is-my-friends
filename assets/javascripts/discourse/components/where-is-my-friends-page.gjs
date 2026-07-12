import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { LinkTo } from "@ember/routing";
import { next } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { clipboardCopy } from "discourse/lib/utilities";
import { relativeAge } from "discourse/lib/formatter";
import DButton from "discourse/ui-kit/d-button";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import { i18n } from "discourse-i18n";
import { normalizeCityClient } from "../lib/where-is-my-friends-city";
import { getCurrentPositionAsync } from "../lib/where-is-my-friends-geolocation";
import LocationModeDialog from "./location-mode-dialog";
import VirtualLocationPicker from "./virtual-location-picker";

export default class WhereIsMyFriendsPage extends Component {
  @service currentUser;
  @service modal;
  @service siteSettings;

  @tracked city;
  @tracked region;
  @tracked location;
  @tracked discoveryState;
  @tracked users = [];
  @tracked loading = false;
  @tracked error = null;
  @tracked gpsFallback = false;
  @tracked memberFilter = "";
  @tracked showRegion;
  @tracked inviteFeedback = null;
  @tracked notifyCity;
  @tracked nearbyCityCount = 0;
  @tracked expandedRadius = false;
  @tracked originalRadiusKm = null;
  @tracked expandedRadiusKm = null;
  @tracked autoCity = null;

  constructor() {
    super(...arguments);
    const autoCity = new URLSearchParams(window.location.search).get(
      "auto_city"
    );
    this.city =
      this.args.model.location?.city ??
      autoCity ??
      this.args.model.profile_location ??
      "";
    this.autoCity = autoCity && !this.args.model.location ? autoCity : null;
    this.region = this.args.model.location?.region ?? "";
    this.showRegion = Boolean(this.region);
    this.location = this.args.model.location;
    this.discoveryState = this.args.model.state;
    this.notifyCity =
      this.currentUser?.user_option?.where_is_my_friends_notify_city ?? true;
  }

  get isSetup() {
    return this.discoveryState === "setup";
  }

  get isEmpty() {
    return this.discoveryState === "empty";
  }

  get availableUsers() {
    const username =
      this.currentUser?.username ?? this.args.model.current_user?.username;
    return this.users.filter((user) => user.username !== username);
  }

  get hasUsers() {
    return this.availableUsers.length > 0;
  }

  get showMemberFilter() {
    return this.availableUsers.length >= 10;
  }

  get chatEnabled() {
    return (
      this.siteSettings.chat_enabled && this.currentUser?.has_chat_enabled
    );
  }

  get visibleUsers() {
    const bandOrder = {
      same_city: 0,
      under_5: 1,
      nearby: 2,
      "5_to_20": 3,
      moderate: 4,
      over_20: 5,
      far: 6,
    };
    const query = this.memberFilter.trim().toLocaleLowerCase();
    const users = query
      ? this.availableUsers.filter((user) =>
          [user.name, user.username].some((value) =>
            value?.toLocaleLowerCase().includes(query)
          )
        )
      : this.availableUsers;

    const useChat = this.chatEnabled;
    return [...users]
      .sort(
        (a, b) =>
          (bandOrder[a.distance_band ?? "same_city"] ?? 99) -
          (bandOrder[b.distance_band ?? "same_city"] ?? 99)
      )
      .map((user) => ({
        ...user,
        distance_label: i18n(
          `where_is_my_friends.distance_bands.${user.distance_band ?? "same_city"}`
        ),
        action_url: useChat
          ? `/chat/new-message?recipients=${encodeURIComponent(user.username)}`
          : user.message_url,
        last_active_label: user.last_seen_at
          ? relativeAge(new Date(user.last_seen_at), { format: "tiny" })
          : null,
      }));
  }

  get resultsSummary() {
    const count = this.availableUsers.length;
    return i18n(
      count === 1
        ? "where_is_my_friends.results_count_one"
        : "where_is_my_friends.results_count_other",
      {
        city: this.location.city,
        count,
        radius: this.discoveryRadiusKm,
      }
    );
  }

  get discoveryRadiusKm() {
    return (
      this.location?.discovery_radius_km ??
      this.args.model.settings?.default_discovery_radius_km ??
      100
    );
  }

  get discoveryRadiusOptions() {
    return (
      this.args.model.settings?.discovery_radius_options_km ?? [50, 100, 200]
    );
  }

  get discoveryRadiusButtons() {
    return this.discoveryRadiusOptions.map((radius) => ({
      radius,
      selected: radius === this.discoveryRadiusKm,
      label: i18n("where_is_my_friends.discovery_radius_option", { radius }),
    }));
  }

  get participantProof() {
    const participants = this.args.model.active_participants;
    if (!participants || participants.suppressed) {
      return i18n("where_is_my_friends.participant_proof_generic");
    }

    if (participants.city_count) {
      return i18n("where_is_my_friends.global_stats", {
        count: participants.count,
        city_count: participants.city_count,
      });
    }

    return i18n("where_is_my_friends.participant_proof_count", {
      count: participants.count,
    });
  }

  get cityPreview() {
    const input = this.city.trim().toLowerCase();
    if (!input) {
      return null;
    }

    const normalizedInput = normalizeCityClient(input);
    const match = this.args.model.city_suggestions?.find(
      (suggestion) =>
        suggestion.city.toLowerCase() === input ||
        suggestion.city_key === normalizedInput
    );

    if (!match || match.count < 1) {
      return null;
    }

    const threshold =
      this.args.model.settings?.aggregate_privacy_threshold ?? 3;
    if (match.count < threshold) {
      return null;
    }

    return i18n("where_is_my_friends.city_member_count", {
      count: match.count,
      city: match.city,
    });
  }

  get cityNormalizationHint() {
    const raw = this.city.trim();
    if (!raw) {
      return null;
    }

    const normalized = normalizeCityClient(raw);
    const comparable = raw.replace(/\s+/g, " ").toLowerCase();
    if (normalized === comparable) {
      return null;
    }

    return i18n("where_is_my_friends.city_will_match_as", { normalized });
  }

  @action
  initialize() {
    void this.recordEvent("page_view");
    if (this.discoveryState === "ready") {
      void this.loadResults();
    }
  }

  @action
  updateCity(event) {
    this.city = event.target.value;
  }

  @action
  updateRegion(event) {
    this.region = event.target.value;
  }

  @action
  revealRegion() {
    this.showRegion = true;
  }

  @action
  updateMemberFilter(event) {
    this.memberFilter = event.target.value;
  }

  @action
  async saveCity() {
    if (!this.city.trim() || this.loading) {
      return;
    }

    this.loading = true;
    this.error = null;
    void this.recordEvent("setup_started", { location_mode: "city" });

    try {
      const response = await ajax("/where-is-my-friends/locations.json", {
        type: "POST",
        data: {
          city: this.city.trim(),
          region: this.region.trim(),
          discovery_mode: "city",
          discovery_radius_km: this.discoveryRadiusKm,
        },
      });
      this.location = response.location;
      this.discoveryState = response.state;
      void this.recordEvent("location_saved", { location_mode: "city" });
      await this.loadResults();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  async loadResults() {
    this.loading = true;
    this.error = null;

    try {
      const response = await ajax(
        "/where-is-my-friends/locations/nearby.json"
      );
      this.users = response.users ?? [];
      this.nearbyCityCount = response.nearby_city_count ?? 0;
      this.expandedRadius = response.expanded_radius ?? false;
      this.originalRadiusKm = response.original_radius_km ?? null;
      this.expandedRadiusKm = response.expanded_radius_km ?? null;
      this.discoveryState = this.availableUsers.length > 0 ? "ready" : "empty";
      void this.recordEvent("results_viewed", {
        location_mode: this.location?.discovery_mode ?? "city",
        result_count: this.availableUsers.length,
      });
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async selectDiscoveryRadius(radiusKm) {
    if (!this.location || this.loading || radiusKm === this.discoveryRadiusKm) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await ajax("/where-is-my-friends/locations.json", {
        type: "POST",
        data: {
          city: this.location.city,
          region: this.location.region ?? "",
          discovery_mode: this.location.discovery_mode ?? "city",
          discovery_radius_km: radiusKm,
        },
      });
      this.location = response.location;
      this.discoveryState = response.state;
      await this.loadResults();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  openAdvancedLocation() {
    this.gpsFallback = false;
    this.modal.show(LocationModeDialog, {
      model: {
        onGps: () => this.upgradeWithGps(),
        onMap: () => next(() => this.openMapPicker()),
      },
    });
  }

  @action
  openMapPicker() {
    this.modal.show(VirtualLocationPicker, {
      model: {
        settings: this.args.model.settings,
        onConfirm: (coordinates) => this.savePrecise("map", coordinates),
      },
    });
  }

  async upgradeWithGps() {
    this.loading = true;
    this.error = null;
    try {
      const position = await getCurrentPositionAsync();
      await this.savePrecise("gps", {
        latitude: position.coords.latitude,
        longitude: position.coords.longitude,
        location_accuracy: position.coords.accuracy,
      });
    } catch {
      this.gpsFallback = true;
      this.loading = false;
    }
  }

  async savePrecise(discoveryMode, coordinates) {
    this.loading = true;
    this.error = null;
    try {
      const response = await ajax("/where-is-my-friends/locations.json", {
        type: "POST",
        data: {
          city: this.location.city,
          region: this.location.region ?? "",
          discovery_mode: discoveryMode,
          ...coordinates,
        },
      });
      this.location = response.location;
      this.discoveryState = response.state;
      void this.recordEvent("location_saved", { location_mode: discoveryMode });
      await this.loadResults();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  editLocation() {
    this.discoveryState = "setup";
    this.showRegion = Boolean(this.region);
    this.users = [];
    this.memberFilter = "";
    this.gpsFallback = false;
  }

  @action
  async removeLocation() {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      await ajax("/where-is-my-friends/locations.json", { type: "DELETE" });
      void this.recordEvent("location_removed", {
        location_mode: this.location?.discovery_mode ?? "city",
      });
      this.location = null;
      this.users = [];
      this.discoveryState = "setup";
      this.memberFilter = "";
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  trackConnection(eventName) {
    void this.recordEvent(eventName, {
      location_mode: this.location?.discovery_mode ?? "city",
    });
  }

  async recordEvent(eventName, data = {}) {
    try {
      await ajax("/where-is-my-friends/events.json", {
        type: "POST",
        data: { event_name: eventName, ...data },
      });
    } catch {
      // Analytics must never block local discovery.
    }
  }

  @action
  async copyInvite() {
    try {
      const url = new URL("/where-is-my-friends", window.location);
      if (this.location?.city) {
        url.searchParams.set("auto_city", this.location.city);
      }
      await clipboardCopy(url.href);
      this.inviteFeedback = i18n("where_is_my_friends.invite_copied");
    } catch {
      this.inviteFeedback = i18n("where_is_my_friends.invite_copy_failed");
    }
  }

  @action
  async toggleNotifyCity() {
    this.notifyCity = !this.notifyCity;
    try {
      await ajax(`/u/${this.currentUser.username}.json`, {
        type: "PUT",
        data: {
          where_is_my_friends_notify_city: this.notifyCity,
        },
      });
    } catch {
      this.notifyCity = !this.notifyCity;
    }
  }

  errorMessage(error) {
    const response = error?.jqXHR?.responseJSON ?? error?.responseJSON;
    return (
      response?.errors?.[0] ?? i18n("where_is_my_friends.generic_error")
    );
  }

  <template>
    <main
      class="where-is-my-friends"
      data-state={{this.discoveryState}}
      {{didInsert this.initialize}}
    >
      <header class="where-is-my-friends__header">
        <p class="where-is-my-friends__eyebrow">{{i18n
            "where_is_my_friends.eyebrow"
          }}</p>
        <h1>{{i18n "where_is_my_friends.title"}}</h1>
        <p>{{i18n "where_is_my_friends.description"}}</p>
      </header>

      {{#if this.error}}
        <div class="alert alert-error" data-test-error>{{this.error}}</div>
      {{/if}}

      {{#if this.isSetup}}
        <section class="where-is-my-friends__setup">
          <h2>{{i18n "where_is_my_friends.setup_title"}}</h2>
          <p>{{i18n "where_is_my_friends.setup_description"}}</p>
          <p
            class="where-is-my-friends__participant-proof"
            data-test-participant-proof
          >{{this.participantProof}}</p>
          <label for="where-is-my-friends-city">{{i18n
              "where_is_my_friends.city"
            }}</label>
          <input
            id="where-is-my-friends-city"
            type="text"
            value={{this.city}}
            list="where-is-my-friends-city-suggestions"
            autocomplete="address-level2"
            placeholder={{i18n "where_is_my_friends.city_placeholder"}}
            data-test-city-input
            {{on "input" this.updateCity}}
          />
          <datalist id="where-is-my-friends-city-suggestions">
            {{#each @model.city_suggestions as |suggestion|}}
              <option value={{suggestion.city}}></option>
            {{/each}}
          </datalist>
          {{#if this.autoCity}}
            <p
              class="where-is-my-friends__auto-city-hint"
              data-test-auto-city-hint
            >{{i18n
                "where_is_my_friends.auto_city_hint"
                city=this.autoCity
              }}</p>
          {{/if}}
          {{#if this.cityPreview}}
            <p
              class="where-is-my-friends__city-preview"
              data-test-city-preview
            >{{this.cityPreview}}</p>
          {{/if}}
          {{#if this.cityNormalizationHint}}
            <p
              class="where-is-my-friends__city-hint"
              data-test-city-hint
            >{{this.cityNormalizationHint}}</p>
          {{/if}}
          {{#if this.showRegion}}
            <label for="where-is-my-friends-region">{{i18n
                "where_is_my_friends.region_optional"
              }}</label>
            <input
              id="where-is-my-friends-region"
              type="text"
              value={{this.region}}
              autocomplete="address-level1"
              data-test-region-field
              {{on "input" this.updateRegion}}
            />
          {{else}}
            <DButton
              @action={{this.revealRegion}}
              @label="where_is_my_friends.add_region"
              @icon="plus"
              class="btn-flat where-is-my-friends__add-region"
              data-test-toggle-region
            />
          {{/if}}
          <DButton
            @action={{this.saveCity}}
            @label="where_is_my_friends.save_city"
            @icon="location-dot"
            @disabled={{this.loading}}
            class="btn-primary"
            data-test-save-city
          />
          <p class="where-is-my-friends__privacy">{{i18n
              "where_is_my_friends.city_privacy"
            }}</p>
        </section>
      {{else}}
        <section
          class="where-is-my-friends__location-summary"
          data-test-location-mode={{this.location.discovery_mode}}
        >
          <div>
            <span>{{i18n "where_is_my_friends.your_city"}}</span>
            <strong>{{this.location.city}}</strong>
          </div>
          <div
            class="where-is-my-friends__radius"
            role="group"
            aria-label={{i18n "where_is_my_friends.discovery_radius"}}
            data-test-discovery-radius
          >
            <span>{{i18n "where_is_my_friends.discovery_radius"}}</span>
            {{#each this.discoveryRadiusButtons as |option|}}
              <DButton
                @action={{fn this.selectDiscoveryRadius option.radius}}
                @translatedLabel={{option.label}}
                @disabled={{this.loading}}
                class={{if option.selected "btn-primary" "btn-flat"}}
                data-test-discovery-radius-option={{option.radius}}
              />
            {{/each}}
          </div>
          <details
            class="where-is-my-friends__location-settings"
            data-test-location-settings
          >
            <summary
              class="btn btn-flat"
              data-test-location-settings-toggle
            >{{i18n "where_is_my_friends.location_settings"}}</summary>
            <div class="where-is-my-friends__location-actions">
              {{#if @model.settings.virtual_location_enabled}}
                <DButton
                  @action={{this.openAdvancedLocation}}
                  @label="where_is_my_friends.advanced_location"
                  @icon="map-location-dot"
                  class="btn-flat"
                  data-test-advanced-location
                />
              {{/if}}
              <DButton
                @action={{this.editLocation}}
                @label="where_is_my_friends.update_city"
                @icon="pencil"
                class="btn-flat"
                data-test-update-location
              />
              <DButton
                @action={{this.removeLocation}}
                @label="where_is_my_friends.remove_location"
                @icon="trash-can"
                class="btn-danger"
                data-test-remove-location
              />
            </div>
          </details>
        </section>

        {{#if this.gpsFallback}}
          <p class="alert alert-info" data-test-gps-fallback>{{i18n
              "where_is_my_friends.gps_city_fallback"
            }}</p>
        {{/if}}

        {{#if this.loading}}
          <div class="where-is-my-friends__loading" role="status">
            {{i18n "where_is_my_friends.loading_results"}}
          </div>
          <div
            class="where-is-my-friends__skeleton-grid"
            aria-hidden="true"
          >
            <article data-test-result-skeleton></article>
            <article data-test-result-skeleton></article>
            <article data-test-result-skeleton></article>
          </div>
        {{else if this.hasUsers}}
          <section class="where-is-my-friends__results">
            {{#if this.expandedRadius}}
              <p class="alert alert-info" data-test-expanded-radius>
                {{i18n
                  "where_is_my_friends.expanded_radius_notice"
                  original_radius=this.originalRadiusKm
                  expanded_radius=this.expandedRadiusKm
                }}
              </p>
            {{/if}}
            <div class="where-is-my-friends__results-heading">
              <h2 data-test-results-summary>{{this.resultsSummary}}</h2>
              <LinkTo
                @route="full-page-search"
                @query={{hash q=this.location.city}}
                class="btn"
                aria-label={{i18n
                  "where_is_my_friends.browse_topics_for"
                  city=this.location.city
                }}
                data-test-local-topics
                {{on
                  "click"
                  (fn this.trackConnection "local_topics_clicked")
                }}
              >{{i18n "where_is_my_friends.browse_local_topics"}}</LinkTo>
            </div>
            {{#if this.showMemberFilter}}
              <label class="where-is-my-friends__filter">
                <span>{{i18n "where_is_my_friends.filter_members"}}</span>
                <input
                  type="search"
                  value={{this.memberFilter}}
                  aria-label={{i18n "where_is_my_friends.filter_members"}}
                  placeholder={{i18n
                    "where_is_my_friends.filter_members_placeholder"
                  }}
                  data-test-member-filter
                  {{on "input" this.updateMemberFilter}}
                />
              </label>
            {{/if}}
            <div class="where-is-my-friends__user-grid">
              {{#each this.visibleUsers as |user|}}
                <article
                  class="where-is-my-friends__user-card"
                  data-test-user-card={{user.username}}
                >
                  {{#if user.avatar_template}}
                    {{dAvatar user imageSize="large"}}
                  {{/if}}
                  <div>
                    <h3>
                      {{if user.name user.name user.username}}
                      {{#if user.is_recent}}
                        <span
                          class="where-is-my-friends__new-badge"
                          data-test-new-member-badge
                        >{{i18n
                            "where_is_my_friends.new_member_badge"
                          }}</span>
                      {{/if}}
                    </h3>
                    <LinkTo @route="user" @model={{user.username}}>
                      @{{user.username}}
                    </LinkTo>
                    <p>{{user.city}} · {{user.distance_label}}{{#if
                        user.last_active_label
                      }} · {{user.last_active_label}}{{/if}}</p>
                    {{#if user.bio_excerpt}}
                      <p
                        class="where-is-my-friends__bio"
                        data-test-user-bio
                      >{{user.bio_excerpt}}</p>
                    {{/if}}
                  </div>
                  <div class="where-is-my-friends__user-actions">
                    <LinkTo
                      @route="user"
                      @model={{user.username}}
                      class="btn"
                      aria-label={{i18n
                        "where_is_my_friends.view_profile_for"
                        username=user.username
                      }}
                      data-test-profile-link={{user.username}}
                      {{on
                        "click"
                        (fn this.trackConnection "profile_clicked")
                      }}
                    >{{i18n "where_is_my_friends.view_profile"}}</LinkTo>
                    {{#if user.action_url}}
                      <a
                        class="btn btn-primary"
                        href={{user.action_url}}
                        aria-label={{i18n
                          "where_is_my_friends.message_user"
                          username=user.username
                        }}
                        data-test-message-link={{user.username}}
                        {{on
                          "click"
                          (fn this.trackConnection "message_started")
                        }}
                      >{{i18n
                          (if
                            this.chatEnabled
                            "where_is_my_friends.start_chat"
                            "where_is_my_friends.send_message"
                          )
                        }}</a>
                    {{/if}}
                  </div>
                </article>
              {{/each}}
            </div>
          </section>
        {{else if this.isEmpty}}
          <section class="where-is-my-friends__empty" data-test-empty-state>
            <h2>{{i18n "where_is_my_friends.empty_title" city=this.location.city}}</h2>
            <p>{{this.participantProof}}</p>
            <p>{{i18n
                "where_is_my_friends.global_stats_pioneer"
                city=this.location.city
              }}</p>
            {{#if this.nearbyCityCount}}
              <p
                class="where-is-my-friends__nearby-count"
                data-test-nearby-city-count
              >{{i18n
                  "where_is_my_friends.empty_nearby_count"
                  count=this.nearbyCityCount
                }}</p>
            {{/if}}
            <label
              class="where-is-my-friends__notify-toggle"
              data-test-notify-toggle
            >
              <input
                type="checkbox"
                checked={{this.notifyCity}}
                {{on "change" this.toggleNotifyCity}}
              />
              {{i18n
                "where_is_my_friends.empty_notify_prompt"
                city=this.location.city
              }}
            </label>
            <LinkTo
              @route="full-page-search"
              @query={{hash q=this.location.city}}
              class="btn btn-primary"
              aria-label={{i18n
                "where_is_my_friends.browse_topics_for"
                city=this.location.city
              }}
              data-test-local-topics
              {{on
                "click"
                (fn this.trackConnection "local_topics_clicked")
              }}
            >{{i18n "where_is_my_friends.browse_local_topics"}}</LinkTo>
            <DButton
              @action={{this.copyInvite}}
              @label="where_is_my_friends.copy_invite"
              @icon="link"
              class="btn"
              data-test-copy-invite
            />
            {{#if this.inviteFeedback}}
              <p role="status" data-test-invite-feedback>{{this.inviteFeedback}}</p>
            {{/if}}
            <p data-test-empty-invitation>{{i18n
                "where_is_my_friends.empty_invitation"
              }}</p>
          </section>
        {{/if}}
      {{/if}}
    </main>
  </template>
}
