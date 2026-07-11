import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import { i18n } from "discourse-i18n";

export default class WhereIsMyFriendsPage extends Component {
  @service currentUser;

  @tracked city;
  @tracked region;
  @tracked location;
  @tracked discoveryState;
  @tracked users = [];
  @tracked loading = false;
  @tracked error = null;

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

  get hasUsers() {
    return this.users.length > 0;
  }

  get visibleUsers() {
    const username = this.currentUser?.username ?? this.args.model.current_user?.username;
    return this.users.filter((user) => user.username !== username);
  }

  get localTopicsUrl() {
    return `/search?q=${encodeURIComponent(this.location?.city ?? this.city)}`;
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
      this.discoveryState = this.visibleUsers.length > 0 ? "ready" : "empty";
      void this.recordEvent("results_viewed", {
        location_mode: this.location?.discovery_mode ?? "city",
        result_count: this.visibleUsers.length,
      });
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
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
        <section class="where-is-my-friends__location-summary">
          <div>
            <span>{{i18n "where_is_my_friends.your_city"}}</span>
            <strong>{{this.location.city}}</strong>
          </div>
        </section>

        {{#if this.loading}}
          <div class="where-is-my-friends__loading" role="status">
            {{i18n "where_is_my_friends.loading_results"}}
          </div>
        {{else if this.hasUsers}}
          <section class="where-is-my-friends__results">
            <h2>{{i18n "where_is_my_friends.people_in_city"}}</h2>
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
                    <a href={{user.profile_url}}>@{{user.username}}</a>
                    <p>{{user.city}}</p>
                  </div>
                  <div class="where-is-my-friends__user-actions">
                    <a class="btn btn-primary" href={{user.profile_url}}>{{i18n
                        "where_is_my_friends.view_profile"
                      }}</a>
                    {{#if user.message_url}}
                      <a class="btn" href={{user.message_url}}>{{i18n
                          "where_is_my_friends.send_message"
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
            <p>{{i18n "where_is_my_friends.empty_description"}}</p>
            <a
              class="btn btn-primary"
              href={{this.localTopicsUrl}}
              data-test-local-topics
            >{{i18n "where_is_my_friends.browse_local_topics"}}</a>
          </section>
        {{/if}}
      {{/if}}
    </main>
  </template>
}
