import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { LinkTo } from "@ember/routing";
import DButton from "discourse/ui-kit/d-button";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import { i18n } from "discourse-i18n";
import LocalTopicsPanel from "./local-topics-panel";

export default <template>
  <section
    class="where-is-my-friends__location-summary"
    data-test-location-mode={{@location.discovery_mode}}
  >
    <div>
      <span>{{i18n "where_is_my_friends.your_city"}}</span>
      <strong>{{@location.city}}</strong>
    </div>
    <div
      class="where-is-my-friends__radius"
      role="group"
      aria-label={{i18n "where_is_my_friends.discovery_radius"}}
      data-test-discovery-radius
    >
      <span>{{i18n "where_is_my_friends.discovery_radius"}}</span>
      {{#each @discoveryRadiusButtons as |option|}}
        <DButton
          @action={{fn @selectDiscoveryRadius option.radius}}
          @translatedLabel={{option.label}}
          @disabled={{@loading}}
          class={{if option.selected "btn-primary" "btn-flat"}}
          data-test-discovery-radius-option={{option.radius}}
        />
      {{/each}}
    </div>
    <details
      class="where-is-my-friends__location-settings"
      data-test-location-settings
    >
      <summary class="btn btn-flat" data-test-location-settings-toggle>{{i18n
          "where_is_my_friends.location_settings"
        }}</summary>
      <div class="where-is-my-friends__location-actions">
        {{#if @model.settings.virtual_location_enabled}}
          <DButton
            @action={{@openAdvancedLocation}}
            @label="where_is_my_friends.advanced_location"
            @icon="map-location-dot"
            class="btn-flat"
            data-test-advanced-location
          />
        {{/if}}
        <DButton
          @action={{@editLocation}}
          @label="where_is_my_friends.update_city"
          @icon="pencil"
          class="btn-flat"
          data-test-update-location
        />
        <DButton
          @action={{@removeLocation}}
          @label="where_is_my_friends.remove_location"
          @icon="trash-can"
          class="btn-danger"
          data-test-remove-location
        />
      </div>
    </details>
  </section>

  {{#if @gpsFallback}}
    <p class="alert alert-info" data-test-gps-fallback>{{i18n
        "where_is_my_friends.gps_city_fallback"
      }}</p>
  {{/if}}

  {{#if @loading}}
    <div class="where-is-my-friends__loading" role="status">
      {{i18n "where_is_my_friends.loading_results"}}
    </div>
    <div class="where-is-my-friends__skeleton-grid" aria-hidden="true">
      <article data-test-result-skeleton></article>
      <article data-test-result-skeleton></article>
      <article data-test-result-skeleton></article>
    </div>
  {{else if @hasUsers}}
    <section class="where-is-my-friends__results">
      {{#if @expandedRadius}}
        <p class="alert alert-info" data-test-expanded-radius>
          {{i18n
            "where_is_my_friends.expanded_radius_notice"
            original_radius=@originalRadiusKm
            expanded_radius=@expandedRadiusKm
          }}
        </p>
      {{/if}}
      <div class="where-is-my-friends__results-heading">
        <h2 data-test-results-summary>{{@resultsSummary}}</h2>
      </div>
      {{#if @hasFilterableFields}}
        <div
          class="where-is-my-friends__attribute-filters"
          data-test-attribute-filters
        >
          {{#each @filterGroups as |group|}}
            <div
              class="where-is-my-friends__filter-group"
              data-test-filter-group={{group.key}}
            >
              <span
                class="where-is-my-friends__filter-label"
              >{{group.name}}</span>
              <div
                class="where-is-my-friends__filter-options"
                role="group"
                aria-label={{group.name}}
              >
                {{#each group.buttons as |btn|}}
                  <DButton
                    @action={{fn @selectFilter group.key btn.value}}
                    @translatedLabel={{btn.label}}
                    @disabled={{@loading}}
                    class={{if btn.selected "btn-primary" "btn-flat"}}
                    data-test-filter-option={{if btn.value btn.value "all"}}
                  />
                {{/each}}
              </div>
            </div>
          {{/each}}
        </div>
      {{/if}}
      {{#if @showMemberFilter}}
        <label class="where-is-my-friends__filter">
          <span>{{i18n "where_is_my_friends.filter_members"}}</span>
          <input
            type="search"
            value={{@memberFilter}}
            aria-label={{i18n "where_is_my_friends.filter_members"}}
            placeholder={{i18n
              "where_is_my_friends.filter_members_placeholder"
            }}
            data-test-member-filter
            {{on "input" @updateMemberFilter}}
          />
        </label>
      {{/if}}
      {{#each @displayCityGroups as |group|}}
        <section
          class="where-is-my-friends__city-group"
          data-test-city-group={{group.city_key}}
        >
          {{#unless group.synthetic}}
            <div class="where-is-my-friends__city-group-heading">
              <h3>{{group.heading_label}}</h3>
              <span>{{group.counts_label}}</span>
            </div>
          {{/unless}}
          <div class="where-is-my-friends__user-grid">
            {{#each group.users as |user|}}
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
                      >{{i18n "where_is_my_friends.new_member_badge"}}</span>
                    {{/if}}
                  </h3>
                  <LinkTo @route="user" @model={{user.username}}>
                    @{{user.username}}
                  </LinkTo>
                  <p>{{user.city}}{{#if user.distance_label}}
                      ·
                      {{user.distance_label}}{{/if}}</p>
                  {{#if user.activity_label}}
                    <p
                      class={{if
                        user.online
                        "where-is-my-friends__activity is-online"
                        "where-is-my-friends__activity"
                      }}
                      data-test-user-activity
                    >{{user.activity_label}}</p>
                  {{/if}}
                  {{#if user.custom_field_label}}
                    <p>
                      <span
                        class="where-is-my-friends__user-attrs"
                        data-test-user-attrs
                      >{{user.custom_field_label}}</span>
                    </p>
                  {{/if}}
                  {{#if user.inactive}}
                    {{#unless user.activity_label}}
                      <p
                        class="where-is-my-friends__inactive"
                        data-test-inactive-member
                      >{{i18n "where_is_my_friends.inactive_member"}}</p>
                    {{/unless}}
                  {{/if}}
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
                    {{on "click" (fn @trackConnection "profile_clicked")}}
                  >{{i18n "where_is_my_friends.view_profile"}}</LinkTo>
                  {{#if user.action_url}}
                    <a
                      class="btn"
                      href={{user.action_url}}
                      aria-label={{i18n
                        "where_is_my_friends.message_user"
                        username=user.username
                      }}
                      data-test-message-link={{user.username}}
                      {{on "click" (fn @trackConnection "message_started")}}
                    >{{i18n
                        (if
                          @chatEnabled
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
      {{/each}}
      <p
        class="where-is-my-friends__presence-note"
        data-test-presence-note
      >{{i18n "where_is_my_friends.presence_privacy_note"}}</p>
    </section>
  {{else if @isEmpty}}
    <section class="where-is-my-friends__empty" data-test-empty-state>
      {{#if @hasActiveFilters}}
        <p class="alert alert-info" data-test-filter-empty-hint>{{i18n
            "where_is_my_friends.no_results_with_filters"
          }}</p>
      {{/if}}
      <h2>{{i18n "where_is_my_friends.empty_title" city=@location.city}}</h2>
      <p>{{@participantProof}}</p>
      <p>{{i18n
          "where_is_my_friends.global_stats_pioneer"
          city=@location.city
        }}</p>
      {{#if @nearbyCityCount}}
        <p
          class="where-is-my-friends__nearby-count"
          data-test-nearby-city-count
        >{{i18n
            "where_is_my_friends.empty_nearby_count"
            count=@nearbyCityCount
          }}</p>
      {{/if}}
      <label class="where-is-my-friends__notify-toggle" data-test-notify-toggle>
        <input
          type="checkbox"
          checked={{@notifyCity}}
          {{on "change" @toggleNotifyCity}}
        />
        {{i18n "where_is_my_friends.empty_notify_prompt" city=@location.city}}
      </label>
      <DButton
        @action={{@copyInvite}}
        @label="where_is_my_friends.copy_invite"
        @icon="link"
        class="btn"
        data-test-copy-invite
      />
      {{#if @inviteFeedback}}
        <p role="status" data-test-invite-feedback>{{@inviteFeedback}}</p>
      {{/if}}
      <p data-test-empty-invitation>{{i18n
          "where_is_my_friends.empty_invitation"
        }}</p>
    </section>
  {{/if}}
  <aside class="where-is-my-friends__safety" data-test-safety-tip>
    <strong>{{i18n "where_is_my_friends.safety_title"}}</strong>
    <span>{{i18n "where_is_my_friends.safety_copy"}}</span>
  </aside>
  <LocalTopicsPanel
    @actionUrl={{@localTopicActionUrl}}
    @city={{@location.city}}
    @compose={{false}}
    @onAction={{@trackLocalTopicOpen}}
  />
</template>
