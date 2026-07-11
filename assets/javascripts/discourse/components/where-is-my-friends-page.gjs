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
import DButton from "discourse/ui-kit/d-button";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import { i18n } from "discourse-i18n";
import { getCurrentPositionAsync } from "../lib/where-is-my-friends-geolocation";
import LocationModeDialog from "./location-mode-dialog";
import VirtualLocationPicker from "./virtual-location-picker";

export default class WhereIsMyFriendsPage extends Component {
  @service currentUser;
  @service modal;

  @tracked city;
  @tracked region;
  @tracked location;
  @tracked discoveryState;
  @tracked users = [];
  @tracked loading = false;
  @tracked error = null;
  @tracked gpsFallback = false;
  @tracked memberFilter = "";

  constructor() {
    super(...arguments);
    this.city = this.args.model.location?.city ?? "";
    this.region = this.args.model.location?.region ?? "";
    this.location = this.args.model.location;
    this.discoveryState = this.args.model.state;
  }

  get isSetup() {
    return this.discoveryState === "setup" || this.discoveryState === "expired";
  }

  get isExpired() {
    return this.discoveryState === "expired";
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

  get visibleUsers() {
    const query = this.memberFilter.trim().toLocaleLowerCase();
    const users = query
      ? this.availableUsers.filter((user) =>
          [user.name, user.username].some((value) =>
            value?.toLocaleLowerCase().includes(query)
          )
        )
      : this.availableUsers;

    return users.map((user) => ({
      ...user,
      distance_label: i18n(
        `where_is_my_friends.distance_bands.${user.distance_band ?? "same_city"}`
      ),
    }));
  }

  get formattedExpiry() {
    if (!this.location?.expires_at) {
      return null;
    }
    return new Date(this.location.expires_at).toLocaleDateString();
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

  errorMessage(error) {
    const response = error?.jqXHR?.responseJSON ?? error?.responseJSON;
    return response?.errors?.[0] ?? "Unable to load local discovery.";
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
          {{#if this.isExpired}}
            <p class="alert alert-info">{{i18n
                "where_is_my_friends.expired_notice"
              }}</p>
          {{/if}}
          <h2>{{i18n "where_is_my_friends.setup_title"}}</h2>
          <p>{{i18n "where_is_my_friends.setup_description"}}</p>
          <label for="where-is-my-friends-city">{{i18n
              "where_is_my_friends.city"
            }}</label>
          <input
            id="where-is-my-friends-city"
            type="text"
            value={{this.city}}
            autocomplete="address-level2"
            data-test-city-input
            {{on "input" this.updateCity}}
          />
          <label for="where-is-my-friends-region">{{i18n
              "where_is_my_friends.region_optional"
            }}</label>
          <input
            id="where-is-my-friends-region"
            type="text"
            value={{this.region}}
            autocomplete="address-level1"
            {{on "input" this.updateRegion}}
          />
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
            {{#if this.formattedExpiry}}
              <span>{{i18n "where_is_my_friends.expires_on"}}
                <time
                  datetime={{this.location.expires_at}}
                  data-test-location-expiry
                >{{this.formattedExpiry}}</time></span>
            {{/if}}
          </div>
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
        {{else if this.hasUsers}}
          <section class="where-is-my-friends__results">
            <h2>{{i18n "where_is_my_friends.people_in_city"}}</h2>
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
                    <h3>{{if user.name user.name user.username}}</h3>
                    <LinkTo @route="user" @model={{user.username}}>
                      @{{user.username}}
                    </LinkTo>
                    <p>{{user.city}} · {{user.distance_label}}</p>
                  </div>
                  <div class="where-is-my-friends__user-actions">
                    <LinkTo
                      @route="user"
                      @model={{user.username}}
                      class="btn btn-primary"
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
                    {{#if user.message_url}}
                      <a
                        class="btn"
                        href={{user.message_url}}
                        aria-label={{i18n
                          "where_is_my_friends.message_user"
                          username=user.username
                        }}
                        data-test-message-link={{user.username}}
                        {{on
                          "click"
                          (fn this.trackConnection "message_started")
                        }}
                      >{{i18n "where_is_my_friends.send_message"}}</a>
                    {{/if}}
                  </div>
                </article>
              {{/each}}
            </div>
          </section>
        {{else if this.isEmpty}}
          <section class="where-is-my-friends__empty" data-test-empty-state>
            <h2>{{i18n "where_is_my_friends.empty_title" city=this.location.city}}</h2>
            <p>{{i18n "where_is_my_friends.empty_description"}}</p>
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
            <p data-test-empty-invitation>{{i18n
                "where_is_my_friends.empty_invitation"
              }}</p>
          </section>
        {{/if}}
      {{/if}}
    </main>
  </template>
}
