import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import UserTagChips from "./user-tag-chips";

export default <template>
  <section class="interest-onboarding__results">
    <div class="interest-onboarding__results-header">
      <div>
        <h2>{{i18n "where_is_my_friends.interests.results_title"}}</h2>
        <p>{{i18n "where_is_my_friends.interests.results_description"}}</p>
      </div>
      <DButton
        @action={{fn @on.manage "edit"}}
        @label="where_is_my_friends.interests.edit"
        @icon="pencil"
        class="btn-flat"
        data-test-edit-interests
      />
    </div>

    {{#if @state.recommendations.hasRecommendations}}
      {{#if @state.recommendations.topics.length}}
        <h3>{{i18n "where_is_my_friends.interests.recommended_topics"}}</h3>
        <div class="interest-onboarding__topic-grid">
          {{#each @state.recommendations.topics as |topic|}}
            <article data-test-recommended-topic={{topic.id}}>
              <a
                href={{topic.url}}
                {{on "click" (fn @on.trackOpen "topic" topic)}}
              >
                <h4>{{topic.fancy_title}}</h4>
              </a>
              <p>{{i18n "where_is_my_friends.interests.topic_reason"}}
                {{#each topic.matching_interests as |interest|}}
                  <span class="interest-onboarding__reason">
                    {{interest.name}}
                  </span>
                {{/each}}
              </p>
              <DButton
                @action={{fn @on.dismiss "topic" topic}}
                @label="where_is_my_friends.interests.not_interested"
                @disabled={{@state.loading}}
                class="btn-flat"
                data-test-dismiss-topic={{topic.id}}
              />
            </article>
          {{/each}}
        </div>
      {{/if}}

      {{#if @state.recommendations.users.length}}
        <h3>{{i18n "where_is_my_friends.interests.recommended_people"}}</h3>
        <div class="interest-onboarding__people-grid">
          {{#each @state.recommendations.users as |user|}}
            <article data-test-recommended-user={{user.username}}>
              <div>
                <a
                  href={{user.profile_url}}
                  {{on "click" (fn @on.trackOpen "user" user)}}
                >
                  <h4>{{if user.name user.name user.username}}</h4>
                  <span>@{{user.username}}</span>
                </a>
                {{#if user.bio_excerpt}}
                  <p>{{user.bio_excerpt}}</p>
                {{/if}}
              </div>
              <p>
                {{i18n "where_is_my_friends.interests.person_reason"}}
                {{#each user.reason_interests as |interest|}}
                  <span class="interest-onboarding__reason">
                    {{interest.name}}
                  </span>
                {{/each}}
              </p>
              <UserTagChips
                @username={{user.username}}
                @tags={{user.user_tags}}
              />
              {{#if user.representative_topics.length}}
                <ul>
                  {{#each user.representative_topics as |topic|}}
                    <li>
                      <a
                        href={{topic.url}}
                        {{on "click" (fn @on.trackOpen "user" user)}}
                      >{{topic.title}}</a>
                    </li>
                  {{/each}}
                </ul>
              {{/if}}
              {{#if @state.invitationsEnabled}}
                {{#if user.invitation_interests.length}}
                  <DButton
                    @action={{fn @on.manage "invite" user}}
                    @label="where_is_my_friends.practice_invitations.invite"
                    @icon="user-plus"
                    @disabled={{@state.loading}}
                    class="btn-primary"
                    data-test-invite-user={{user.id}}
                  />
                {{/if}}
              {{/if}}
              <DButton
                @action={{fn @on.dismiss "user" user}}
                @label="where_is_my_friends.interests.not_interested"
                @disabled={{@state.loading}}
                class="btn-flat"
                data-test-dismiss-user={{user.id}}
              />
            </article>
          {{/each}}
        </div>
      {{/if}}
    {{else}}
      <div class="interest-onboarding__empty" data-test-recommendations-empty>
        <h3>{{i18n "where_is_my_friends.interests.empty_title"}}</h3>
        <p>{{i18n "where_is_my_friends.interests.empty_description"}}</p>
      </div>
    {{/if}}

    <details class="interest-onboarding__settings">
      <summary>{{i18n "where_is_my_friends.interests.settings"}}</summary>
      <p>{{i18n "where_is_my_friends.interests.disable_description"}}</p>
      <DButton
        @action={{fn @on.manage "disable"}}
        @label="where_is_my_friends.interests.disable"
        @icon="trash-can"
        @disabled={{@state.loading}}
        class="btn-danger"
        data-test-disable-personalization
      />
    </details>
  </section>
</template>
