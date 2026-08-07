import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import LocalTopicsPanel from "./local-topics-panel";

export default <template>
  <section class="where-is-my-friends__setup">
    <h2>{{i18n "where_is_my_friends.setup_title"}}</h2>
    <p>{{i18n "where_is_my_friends.setup_description"}}</p>
    <p
      class="where-is-my-friends__participant-proof"
      data-test-participant-proof
    >{{@state.participantProof}}</p>
    {{#if @state.hasCityDirectory}}
      <div class="where-is-my-friends__directory">
        {{#if @state.cityDirectory.active.length}}
          <section data-test-city-directory-active>
            <h3>{{i18n "where_is_my_friends.active_cities"}}</h3>
            <div class="where-is-my-friends__city-grid">
              {{#each @state.cityDirectory.active as |entry|}}
                <button
                  type="button"
                  class="where-is-my-friends__city-card"
                  data-test-city-card={{entry.city_key}}
                  {{on "click" (fn @on.previewSuggestedCity entry.city)}}
                >
                  <strong>{{entry.city}}</strong>
                  <span>
                    {{#if entry.counts_suppressed}}
                      {{i18n "where_is_my_friends.aggregate_counts_suppressed"}}
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
        {{#if @state.cityDirectory.growing.length}}
          <section data-test-city-directory-growing>
            <h3>{{i18n "where_is_my_friends.growing_cities"}}</h3>
            <div class="where-is-my-friends__city-grid">
              {{#each @state.cityDirectory.growing as |entry|}}
                <button
                  type="button"
                  class="where-is-my-friends__city-card"
                  data-test-city-card={{entry.city_key}}
                  {{on "click" (fn @on.previewSuggestedCity entry.city)}}
                >
                  <strong>{{entry.city}}</strong>
                  <span>
                    {{#if entry.counts_suppressed}}
                      {{i18n "where_is_my_friends.aggregate_counts_suppressed"}}
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
      value={{@state.city}}
      list="where-is-my-friends-city-suggestions"
      autocomplete="address-level2"
      placeholder={{i18n "where_is_my_friends.city_placeholder"}}
      data-test-city-input
      {{on "input" @on.updateCity}}
    />
    <datalist id="where-is-my-friends-city-suggestions">
      {{#each @state.cityOptions as |suggestion|}}
        <option value={{suggestion.city}}></option>
      {{/each}}
    </datalist>
    {{#if @state.autoCity}}
      <p
        class="where-is-my-friends__auto-city-hint"
        data-test-auto-city-hint
      >{{i18n "where_is_my_friends.auto_city_hint" city=@state.autoCity}}</p>
    {{/if}}
    {{#if @state.cityPreview}}
      <p
        class="where-is-my-friends__city-preview"
        data-test-city-preview
      >{{@state.cityPreview}}</p>
    {{/if}}
    {{#if @state.cityNormalizationHint}}
      <p
        class="where-is-my-friends__city-hint"
        data-test-city-hint
      >{{@state.cityNormalizationHint}}</p>
    {{/if}}
    {{#if @state.showRegion}}
      <label for="where-is-my-friends-region">{{i18n
          "where_is_my_friends.region_optional"
        }}</label>
      <input
        id="where-is-my-friends-region"
        type="text"
        value={{@state.region}}
        autocomplete="address-level1"
        data-test-region-field
        {{on "input" @on.updateRegion}}
      />
    {{else}}
      <DButton
        @action={{@on.revealRegion}}
        @label="where_is_my_friends.add_region"
        @icon="plus"
        class="btn-flat where-is-my-friends__add-region"
        data-test-toggle-region
      />
    {{/if}}
    {{#if @state.hasCityDirectory}}
      <DButton
        @action={{@on.previewCurrentCity}}
        @label="where_is_my_friends.preview_city"
        @icon="magnifying-glass-location"
        @disabled={{@state.previewLoading}}
        class="btn-primary"
        data-test-preview-city
      />
      {{#if @state.networkPreview}}
        <section
          class="where-is-my-friends__network-preview"
          data-test-city-network-preview
        >
          <h3>{{@state.networkPreview.city.city}}</h3>
          <p>
            {{#if @state.networkPreview.city.counts_suppressed}}
              {{i18n "where_is_my_friends.aggregate_counts_suppressed"}}
            {{else}}
              {{i18n
                "where_is_my_friends.preview_city_counts"
                active=@state.networkPreview.city.recent_active_count
                joined=@state.networkPreview.city.joined_count
              }}
            {{/if}}
          </p>
          {{#unless @state.networkPreview.city.canonical}}
            <p class="alert alert-info">{{i18n
                "where_is_my_friends.unverified_city_notice"
              }}</p>
          {{/unless}}
          {{#if @state.previewRadiusButtons.length}}
            <div
              class="where-is-my-friends__preview-radii"
              role="group"
              aria-label={{i18n
                "where_is_my_friends.recommended_activity_range"
              }}
            >
              {{#each @state.previewRadiusButtons as |option|}}
                <DButton
                  @action={{fn @on.selectPreviewRadius option.radius_km}}
                  @translatedLabel={{option.label}}
                  class={{if option.selected "btn-primary" "btn-flat"}}
                  data-test-preview-radius={{option.radius_km}}
                />
              {{/each}}
            </div>
          {{/if}}
          {{#if @state.networkPreview.nearby_cities.length}}
            <div class="where-is-my-friends__preview-nearby">
              <h4>{{i18n "where_is_my_friends.nearby_city_network"}}</h4>
              {{#each @state.networkPreview.nearby_cities as |nearby|}}
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
          {{#if @state.networkPreview.local_topic_compose_url}}
            <LocalTopicsPanel
              @actionUrl={{@state.networkPreview.local_topic_compose_url}}
              @city={{@state.networkPreview.city.city}}
              @compose={{true}}
              @onAction={{@on.trackLocalTopicCompose}}
            />
          {{/if}}
          <fieldset class="where-is-my-friends__join-notifications">
            <legend>{{i18n "where_is_my_friends.join_notifications"}}</legend>
            <label>
              <input
                type="checkbox"
                checked={{@state.notifyCity}}
                data-test-join-notify-city
                {{on "change" @on.toggleJoinNotifyCity}}
              />
              {{i18n "where_is_my_friends.notify_city_members"}}
            </label>
            <label>
              <input
                type="checkbox"
                checked={{@state.notifyNearby}}
                data-test-join-notify-nearby
                {{on "change" @on.toggleJoinNotifyNearby}}
              />
              {{i18n "where_is_my_friends.notify_nearby_members"}}
            </label>
          </fieldset>
          <DButton
            @action={{@on.saveCity}}
            @translatedLabel={{@state.previewJoinLabel}}
            @icon="location-dot"
            @disabled={{@state.loading}}
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
            checked={{@state.notifyCity}}
            data-test-join-notify-city
            {{on "change" @on.toggleJoinNotifyCity}}
          />
          {{i18n "where_is_my_friends.notify_city_members"}}
        </label>
        <label>
          <input
            type="checkbox"
            checked={{@state.notifyNearby}}
            data-test-join-notify-nearby
            {{on "change" @on.toggleJoinNotifyNearby}}
          />
          {{i18n "where_is_my_friends.notify_nearby_members"}}
        </label>
      </fieldset>
      <DButton
        @action={{@on.saveCity}}
        @label="where_is_my_friends.save_city"
        @icon="location-dot"
        @disabled={{@state.loading}}
        class="btn-primary"
        data-test-save-city
      />
    {{/if}}
    <p class="where-is-my-friends__privacy">{{i18n
        "where_is_my_friends.city_privacy"
      }}</p>
  </section>
</template>
