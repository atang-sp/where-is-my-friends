import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import LocalTopicsPanel from "./local-topics-panel";

export default class WhereIsMyFriendsSetupPanel extends Component {
  @action
  updateCity(event) {
    this.args.on.change({ city: event.target.value });
  }

  @action
  updateRegion(event) {
    this.args.on.change({ region: event.target.value });
  }

  @action
  revealRegion() {
    this.args.on.change({ showRegion: true });
  }

  @action
  selectPreviewRadius(radiusKm) {
    this.args.on.change({ previewRadius: radiusKm });
  }

  @action
  toggleCityNotifications() {
    this.args.on.change({ notifyCity: !this.args.state.notifications.city });
  }

  @action
  toggleNearbyNotifications() {
    this.args.on.change({
      notifyNearby: !this.args.state.notifications.nearby,
    });
  }

  <template>
    <section class="where-is-my-friends__setup">
      <h2>{{i18n "where_is_my_friends.setup_title"}}</h2>
      <p>{{i18n "where_is_my_friends.setup_description"}}</p>
      <p
        class="where-is-my-friends__participant-proof"
        data-test-participant-proof
      >{{@state.proof}}</p>
      {{#if @state.directory.visible}}
        <div class="where-is-my-friends__directory">
          {{#if @state.directory.value.active.length}}
            <section data-test-city-directory-active>
              <h3>{{i18n "where_is_my_friends.active_cities"}}</h3>
              <div class="where-is-my-friends__city-grid">
                {{#each @state.directory.value.active as |entry|}}
                  <button
                    type="button"
                    class="where-is-my-friends__city-card"
                    data-test-city-card={{entry.city_key}}
                    {{on "click" (fn @on.previewCity entry.city)}}
                  >
                    <strong>{{entry.city}}</strong>
                    <span>
                      {{#if entry.counts_suppressed}}
                        {{i18n
                          "where_is_my_friends.aggregate_counts_suppressed"
                        }}
                      {{else}}
                        {{i18n
                          "where_is_my_friends.city_directory_counts"
                          active=entry.recent_active_count
                          joined=entry.joined_count
                        }}
                      {{/if}}
                    </span>
                  </button>
                {{/each}}
              </div>
            </section>
          {{/if}}
          {{#if @state.directory.value.growing.length}}
            <section data-test-city-directory-growing>
              <h3>{{i18n "where_is_my_friends.growing_cities"}}</h3>
              <div class="where-is-my-friends__city-grid">
                {{#each @state.directory.value.growing as |entry|}}
                  <button
                    type="button"
                    class="where-is-my-friends__city-card"
                    data-test-city-card={{entry.city_key}}
                    {{on "click" (fn @on.previewCity entry.city)}}
                  >
                    <strong>{{entry.city}}</strong>
                    <span>
                      {{#if entry.counts_suppressed}}
                        {{i18n
                          "where_is_my_friends.aggregate_counts_suppressed"
                        }}
                      {{else}}
                        {{i18n
                          "where_is_my_friends.city_directory_counts"
                          active=entry.recent_active_count
                          joined=entry.joined_count
                        }}
                      {{/if}}
                    </span>
                  </button>
                {{/each}}
              </div>
            </section>
          {{/if}}
        </div>
      {{/if}}
      <label for="where-is-my-friends-city">{{i18n
          "where_is_my_friends.city"
        }}</label>
      <input
        id="where-is-my-friends-city"
        type="text"
        value={{@state.form.city}}
        list="where-is-my-friends-city-suggestions"
        autocomplete="address-level2"
        placeholder={{i18n "where_is_my_friends.city_placeholder"}}
        data-test-city-input
        {{on "input" this.updateCity}}
      />
      <datalist id="where-is-my-friends-city-suggestions">
        {{#each @state.directory.options as |suggestion|}}
          <option value={{suggestion.city}}></option>
        {{/each}}
      </datalist>
      {{#if @state.form.autoCity}}
        <p
          class="where-is-my-friends__auto-city-hint"
          data-test-auto-city-hint
        >{{i18n
            "where_is_my_friends.auto_city_hint"
            city=@state.form.autoCity
          }}</p>
      {{/if}}
      {{#if @state.form.cityPreview}}
        <p
          class="where-is-my-friends__city-preview"
          data-test-city-preview
        >{{@state.form.cityPreview}}</p>
      {{/if}}
      {{#if @state.form.normalizationHint}}
        <p
          class="where-is-my-friends__city-hint"
          data-test-city-hint
        >{{@state.form.normalizationHint}}</p>
      {{/if}}
      {{#if @state.form.showRegion}}
        <label for="where-is-my-friends-region">{{i18n
            "where_is_my_friends.region_optional"
          }}</label>
        <input
          id="where-is-my-friends-region"
          type="text"
          value={{@state.form.region}}
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
      {{#if @state.directory.visible}}
        <DButton
          @action={{@on.previewCity}}
          @label="where_is_my_friends.preview_city"
          @icon="magnifying-glass-location"
          @disabled={{@state.preview.loading}}
          class="btn-primary"
          data-test-preview-city
        />
        {{#if @state.preview.value}}
          <section
            class="where-is-my-friends__network-preview"
            data-test-city-network-preview
          >
            <h3>{{@state.preview.value.city.city}}</h3>
            <p>
              {{#if @state.preview.value.city.counts_suppressed}}
                {{i18n "where_is_my_friends.aggregate_counts_suppressed"}}
              {{else}}
                {{i18n
                  "where_is_my_friends.preview_city_counts"
                  active=@state.preview.value.city.recent_active_count
                  joined=@state.preview.value.city.joined_count
                }}
              {{/if}}
            </p>
            {{#unless @state.preview.value.city.canonical}}
              <p class="alert alert-info">{{i18n
                  "where_is_my_friends.unverified_city_notice"
                }}</p>
            {{/unless}}
            {{#if @state.preview.radiusButtons.length}}
              <div
                class="where-is-my-friends__preview-radii"
                role="group"
                aria-label={{i18n
                  "where_is_my_friends.recommended_activity_range"
                }}
              >
                {{#each @state.preview.radiusButtons as |option|}}
                  <DButton
                    @action={{fn this.selectPreviewRadius option.radius_km}}
                    @translatedLabel={{option.label}}
                    class={{if option.selected "btn-primary" "btn-flat"}}
                    data-test-preview-radius={{option.radius_km}}
                  />
                {{/each}}
              </div>
            {{/if}}
            {{#if @state.preview.value.nearby_cities.length}}
              <div class="where-is-my-friends__preview-nearby">
                <h4>{{i18n "where_is_my_friends.nearby_city_network"}}</h4>
                {{#each @state.preview.value.nearby_cities as |nearby|}}
                  <p data-test-preview-nearby-city={{nearby.city_key}}>
                    <strong>{{nearby.city}}</strong>
                    <span>
                      {{#if nearby.counts_suppressed}}
                        {{i18n
                          "where_is_my_friends.nearby_city_counts_suppressed"
                          distance=nearby.approximate_distance_km
                        }}
                      {{else}}
                        {{i18n
                          "where_is_my_friends.nearby_city_counts"
                          distance=nearby.approximate_distance_km
                          active=nearby.recent_active_count
                          joined=nearby.joined_count
                        }}
                      {{/if}}
                    </span>
                  </p>
                {{/each}}
              </div>
            {{/if}}
            {{#if @state.preview.value.local_topic_compose_url}}
              <LocalTopicsPanel
                @actionUrl={{@state.preview.value.local_topic_compose_url}}
                @city={{@state.preview.value.city.city}}
                @compose={{true}}
                @onAction={{@on.trackLocalTopic}}
              />
            {{/if}}
            <fieldset class="where-is-my-friends__join-notifications">
              <legend>{{i18n "where_is_my_friends.join_notifications"}}</legend>
              <label>
                <input
                  type="checkbox"
                  checked={{@state.notifications.city}}
                  data-test-join-notify-city
                  {{on "change" this.toggleCityNotifications}}
                />
                {{i18n "where_is_my_friends.notify_city_members"}}
              </label>
              <label>
                <input
                  type="checkbox"
                  checked={{@state.notifications.nearby}}
                  data-test-join-notify-nearby
                  {{on "change" this.toggleNearbyNotifications}}
                />
                {{i18n "where_is_my_friends.notify_nearby_members"}}
              </label>
            </fieldset>
            <DButton
              @action={{@on.save}}
              @translatedLabel={{@state.preview.joinLabel}}
              @icon="location-dot"
              @disabled={{@state.saving}}
              class="btn-primary"
              data-test-join-city
              data-test-save-city
            />
          </section>
        {{/if}}
      {{else}}
        <fieldset class="where-is-my-friends__join-notifications">
          <legend>{{i18n "where_is_my_friends.join_notifications"}}</legend>
          <label>
            <input
              type="checkbox"
              checked={{@state.notifications.city}}
              data-test-join-notify-city
              {{on "change" this.toggleCityNotifications}}
            />
            {{i18n "where_is_my_friends.notify_city_members"}}
          </label>
          <label>
            <input
              type="checkbox"
              checked={{@state.notifications.nearby}}
              data-test-join-notify-nearby
              {{on "change" this.toggleNearbyNotifications}}
            />
            {{i18n "where_is_my_friends.notify_nearby_members"}}
          </label>
        </fieldset>
        <DButton
          @action={{@on.save}}
          @label="where_is_my_friends.save_city"
          @icon="location-dot"
          @disabled={{@state.saving}}
          class="btn-primary"
          data-test-save-city
        />
      {{/if}}
      <p class="where-is-my-friends__privacy">{{i18n
          "where_is_my_friends.city_privacy"
        }}</p>
    </section>
  </template>
}
