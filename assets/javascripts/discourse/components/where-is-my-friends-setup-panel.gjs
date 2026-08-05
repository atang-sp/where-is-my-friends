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
    >{{@participantProof}}</p>
    {{#if @hasCityDirectory}}
      <div class="where-is-my-friends__directory">
        {{#if @cityDirectory.active.length}}
          <section data-test-city-directory-active>
            <h3>{{i18n "where_is_my_friends.active_cities"}}</h3>
            <div class="where-is-my-friends__city-grid">
              {{#each @cityDirectory.active as |entry|}}
                <button
                  type="button"
                  class="where-is-my-friends__city-card"
                  data-test-city-card={{entry.city_key}}
                  {{on "click" (fn @previewSuggestedCity entry.city)}}
                >
                  <strong>{{entry.city}}</strong>
                  <span>{{i18n
                      "where_is_my_friends.city_directory_counts"
                      active=entry.recent_active_count
                      joined=entry.joined_count
                    }}</span>
                </button>
              {{/each}}
            </div>
          </section>
        {{/if}}
        {{#if @cityDirectory.growing.length}}
          <section data-test-city-directory-growing>
            <h3>{{i18n "where_is_my_friends.growing_cities"}}</h3>
            <div class="where-is-my-friends__city-grid">
              {{#each @cityDirectory.growing as |entry|}}
                <button
                  type="button"
                  class="where-is-my-friends__city-card"
                  data-test-city-card={{entry.city_key}}
                  {{on "click" (fn @previewSuggestedCity entry.city)}}
                >
                  <strong>{{entry.city}}</strong>
                  <span>{{i18n
                      "where_is_my_friends.city_directory_counts"
                      active=entry.recent_active_count
                      joined=entry.joined_count
                    }}</span>
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
      value={{@city}}
      list="where-is-my-friends-city-suggestions"
      autocomplete="address-level2"
      placeholder={{i18n "where_is_my_friends.city_placeholder"}}
      data-test-city-input
      {{on "input" @updateCity}}
    />
    <datalist id="where-is-my-friends-city-suggestions">
      {{#each @cityOptions as |suggestion|}}
        <option value={{suggestion.city}}></option>
      {{/each}}
    </datalist>
    {{#if @autoCity}}
      <p
        class="where-is-my-friends__auto-city-hint"
        data-test-auto-city-hint
      >{{i18n "where_is_my_friends.auto_city_hint" city=@autoCity}}</p>
    {{/if}}
    {{#if @cityPreview}}
      <p
        class="where-is-my-friends__city-preview"
        data-test-city-preview
      >{{@cityPreview}}</p>
    {{/if}}
    {{#if @cityNormalizationHint}}
      <p
        class="where-is-my-friends__city-hint"
        data-test-city-hint
      >{{@cityNormalizationHint}}</p>
    {{/if}}
    {{#if @showRegion}}
      <label for="where-is-my-friends-region">{{i18n
          "where_is_my_friends.region_optional"
        }}</label>
      <input
        id="where-is-my-friends-region"
        type="text"
        value={{@region}}
        autocomplete="address-level1"
        data-test-region-field
        {{on "input" @updateRegion}}
      />
    {{else}}
      <DButton
        @action={{@revealRegion}}
        @label="where_is_my_friends.add_region"
        @icon="plus"
        class="btn-flat where-is-my-friends__add-region"
        data-test-toggle-region
      />
    {{/if}}
    {{#if @hasCityDirectory}}
      <DButton
        @action={{@previewCurrentCity}}
        @label="where_is_my_friends.preview_city"
        @icon="magnifying-glass-location"
        @disabled={{@previewLoading}}
        class="btn-primary"
        data-test-preview-city
      />
      {{#if @networkPreview}}
        <section
          class="where-is-my-friends__network-preview"
          data-test-city-network-preview
        >
          <h3>{{@networkPreview.city.city}}</h3>
          <p>{{i18n
              "where_is_my_friends.preview_city_counts"
              active=@networkPreview.city.recent_active_count
              joined=@networkPreview.city.joined_count
            }}</p>
          {{#unless @networkPreview.city.canonical}}
            <p class="alert alert-info">{{i18n
                "where_is_my_friends.unverified_city_notice"
              }}</p>
          {{/unless}}
          {{#if @previewRadiusButtons.length}}
            <div
              class="where-is-my-friends__preview-radii"
              role="group"
              aria-label={{i18n
                "where_is_my_friends.recommended_activity_range"
              }}
            >
              {{#each @previewRadiusButtons as |option|}}
                <DButton
                  @action={{fn @selectPreviewRadius option.radius_km}}
                  @translatedLabel={{option.label}}
                  class={{if option.selected "btn-primary" "btn-flat"}}
                  data-test-preview-radius={{option.radius_km}}
                />
              {{/each}}
            </div>
          {{/if}}
          {{#if @networkPreview.nearby_cities.length}}
            <div class="where-is-my-friends__preview-nearby">
              <h4>{{i18n "where_is_my_friends.nearby_city_network"}}</h4>
              {{#each @networkPreview.nearby_cities as |nearby|}}
                <p data-test-preview-nearby-city={{nearby.city_key}}>
                  <strong>{{nearby.city}}</strong>
                  <span>{{i18n
                      "where_is_my_friends.nearby_city_counts"
                      distance=nearby.approximate_distance_km
                      active=nearby.recent_active_count
                      joined=nearby.joined_count
                    }}</span>
                </p>
              {{/each}}
            </div>
          {{/if}}
          {{#if @networkPreview.local_topic_compose_url}}
            <LocalTopicsPanel
              @actionUrl={{@networkPreview.local_topic_compose_url}}
              @city={{@networkPreview.city.city}}
              @compose={{true}}
              @onAction={{@trackLocalTopicCompose}}
            />
          {{/if}}
          <fieldset class="where-is-my-friends__join-notifications">
            <legend>{{i18n "where_is_my_friends.join_notifications"}}</legend>
            <label>
              <input
                type="checkbox"
                checked={{@notifyCity}}
                data-test-join-notify-city
                {{on "change" @toggleJoinNotifyCity}}
              />
              {{i18n "where_is_my_friends.notify_city_members"}}
            </label>
            <label>
              <input
                type="checkbox"
                checked={{@notifyNearby}}
                data-test-join-notify-nearby
                {{on "change" @toggleJoinNotifyNearby}}
              />
              {{i18n "where_is_my_friends.notify_nearby_members"}}
            </label>
          </fieldset>
          <DButton
            @action={{@saveCity}}
            @translatedLabel={{@previewJoinLabel}}
            @icon="location-dot"
            @disabled={{@loading}}
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
            checked={{@notifyCity}}
            data-test-join-notify-city
            {{on "change" @toggleJoinNotifyCity}}
          />
          {{i18n "where_is_my_friends.notify_city_members"}}
        </label>
        <label>
          <input
            type="checkbox"
            checked={{@notifyNearby}}
            data-test-join-notify-nearby
            {{on "change" @toggleJoinNotifyNearby}}
          />
          {{i18n "where_is_my_friends.notify_nearby_members"}}
        </label>
      </fieldset>
      <DButton
        @action={{@saveCity}}
        @label="where_is_my_friends.save_city"
        @icon="location-dot"
        @disabled={{@loading}}
        class="btn-primary"
        data-test-save-city
      />
    {{/if}}
    <p class="where-is-my-friends__privacy">{{i18n
        "where_is_my_friends.city_privacy"
      }}</p>
  </section>
</template>
