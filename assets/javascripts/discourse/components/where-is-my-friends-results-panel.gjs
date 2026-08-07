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
    data-test-location-mode={{@state.location.discovery_mode}}
  >
    <div>
      <span>{{i18n "where_is_my_friends.your_city"}}</span>
      <strong>{{@state.location.city}}</strong>
    </div>
    <div
      class="where-is-my-friends__radius"
      role="group"
      aria-label={{i18n "where_is_my_friends.discovery_radius"}}
      data-test-discovery-radius
    >
      <span>{{i18n "where_is_my_friends.discovery_radius"}}</span>
      {{#each @state.discoveryRadiusButtons as |option|}}
        <DButton
          @action={{fn @on.selectDiscoveryRadius option.radius}}
          @translatedLabel={{option.label}}
          @disabled={{@state.loading}}
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
        {{#if @state.virtualLocationEnabled}}
          <DButton
            @action={{@on.openAdvancedLocation}}
            @label="where_is_my_friends.advanced_location"
            @icon="map-location-dot"
            class="btn-flat"
            data-test-advanced-location
          />
        {{/if}}
        <DButton
          @action={{@on.editLocation}}
          @label="where_is_my_friends.update_city"
          @icon="pencil"
          class="btn-flat"
          data-test-update-location
        />
        <DButton
          @action={{@on.removeLocation}}
          @label="where_is_my_friends.remove_location"
          @icon="trash-can"
          class="btn-danger"
          data-test-remove-location
        />
      </div>
    </details>
  </section>

  {{#if @state.gpsFallback}}
    <p class="alert alert-info" data-test-gps-fallback>{{i18n
        "where_is_my_friends.gps_city_fallback"
      }}</p>
  {{/if}}

  {{#if @state.loading}}
    <div class="where-is-my-friends__loading" role="status">
      {{i18n "where_is_my_friends.loading_results"}}
    </div>
    <div class="where-is-my-friends__skeleton-grid" aria-hidden="true">
      <article data-test-result-skeleton></article>
      <article data-test-result-skeleton></article>
      <article data-test-result-skeleton></article>
    </div>
  {{else if @state.hasUsers}}
    {{#if @state.resultsLimited}}
      <p class="alert alert-info" data-test-results-limited>{{i18n
          "where_is_my_friends.results_limited"
        }}</p>
    {{/if}}
    <section class="where-is-my-friends__results">
      {{#if @state.expandedRadius}}
        <p class="alert alert-info" data-test-expanded-radius>
          {{i18n
            "where_is_my_friends.expanded_radius_notice"
            original_radius=@state.originalRadiusKm
            expanded_radius=@state.expandedRadiusKm
          }}
        </p>
      {{/if}}
      <div class="where-is-my-friends__results-heading">
        <h2 data-test-results-summary>{{@state.resultsSummary}}</h2>
      </div>
      {{#if @state.hasFilterableFields}}
        <div
          class="where-is-my-friends__attribute-filters"
          data-test-attribute-filters
        >
          {{#each @state.filterGroups as |group|}}
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
                    @action={{fn @on.selectFilter group.key btn.value}}
                    @translatedLabel={{btn.label}}
                    @disabled={{@state.loading}}
                    class={{if btn.selected "btn-primary" "btn-flat"}}
                    data-test-filter-option={{if btn.value btn.value "all"}}
                  />
                {{/each}}
              </div>
            </div>
          {{/each}}
        </div>
      {{/if}}
      {{#if @state.showMemberFilter}}
        <label class="where-is-my-friends__filter">
          <span>{{i18n "where_is_my_friends.filter_members"}}</span>
          <input
            type="search"
            value={{@state.memberFilter}}
            aria-label={{i18n "where_is_my_friends.filter_members"}}
            placeholder={{i18n
              "where_is_my_friends.filter_members_placeholder"
            }}
            data-test-member-filter
            {{on "input" @on.updateMemberFilter}}
          />
        </label>
      {{/if}}
      {{#each @state.displayCityGroups as |group|}}
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
                    {{on "click" (fn @on.trackConnection "profile_clicked")}}
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
                      {{on "click" (fn @on.trackConnection "message_started")}}
                    >{{i18n
                        (if
                          @state.chatEnabled
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
  {{else if @state.isLimited}}
    <section class="where-is-my-friends__empty" data-test-limited-state>
      <h2>{{i18n "where_is_my_friends.results_limited_title"}}</h2>
      <p>{{i18n "where_is_my_friends.results_limited"}}</p>
    </section>
  {{else if @state.isEmpty}}
    <section class="where-is-my-friends__empty" data-test-empty-state>
      {{#if @state.hasActiveFilters}}
        <p class="alert alert-info" data-test-filter-empty-hint>{{i18n
            "where_is_my_friends.no_results_with_filters"
          }}</p>
      {{/if}}
      <h2>{{i18n
          "where_is_my_friends.empty_title"
          city=@state.location.city
        }}</h2>
      <p>{{@state.participantProof}}</p>
      <p>{{i18n
          "where_is_my_friends.global_stats_pioneer"
          city=@state.location.city
        }}</p>
      {{#if @state.nearbyCityCountSuppressed}}
        <p
          class="where-is-my-friends__nearby-count"
          data-test-nearby-city-count
        >{{i18n "where_is_my_friends.empty_nearby_count_suppressed"}}</p>
      {{else if @state.nearbyCityCount}}
        <p
          class="where-is-my-friends__nearby-count"
          data-test-nearby-city-count
        >{{i18n
            "where_is_my_friends.empty_nearby_count"
            count=@state.nearbyCityCount
          }}</p>
      {{/if}}
      <label class="where-is-my-friends__notify-toggle" data-test-notify-toggle>
        <input
          type="checkbox"
          checked={{@state.notifyCity}}
          {{on "change" @on.toggleNotifyCity}}
        />
        {{i18n
          "where_is_my_friends.empty_notify_prompt"
          city=@state.location.city
        }}
      </label>
      <DButton
        @action={{@on.copyInvite}}
        @label="where_is_my_friends.copy_invite"
        @icon="link"
        class="btn"
        data-test-copy-invite
      />
      {{#if @state.inviteFeedback}}
        <p role="status" data-test-invite-feedback>{{@state.inviteFeedback}}</p>
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
    @actionUrl={{@state.localTopicActionUrl}}
    @city={{@state.location.city}}
    @compose={{false}}
    @onAction={{@on.trackLocalTopicOpen}}
  />
</template>
