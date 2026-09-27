import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import UserTagChips from "./user-tag-chips";

export default class CommunityDiscoveryPeople extends Component {
  <template>
    <section class="community-discovery__section">
      <h3>{{i18n "where_is_my_friends.community_discovery.people_title"}}</h3>
      <div class="community-discovery__grid">
        {{#each @people as |person|}}
          <article data-test-community-person={{person.username}}>
            <div class="community-discovery__person-heading">
              <h4>{{if person.name person.name person.username}}</h4>
              <span>@{{person.username}}</span>
            </div>
            <p data-test-community-person-reason>
              <strong>{{i18n
                  "where_is_my_friends.community_discovery.why"
                }}</strong>
              {{i18n "where_is_my_friends.community_discovery.person_reason"}}
              {{#each person.reason_interests as |interest|}}
                <span>{{interest.name}}</span>
              {{/each}}
            </p>
            <UserTagChips
              @username={{person.username}}
              @tags={{person.user_tags}}
            />
            {{#if person.latest_dynamic}}
              <a
                class="community-discovery__dynamic-preview"
                href={{person.latest_dynamic.url}}
                data-test-community-person-dynamic
                {{on
                  "click"
                  (fn @trackOpen "recommended_user_dynamic_opened" person)
                }}
              >
                <strong>{{i18n
                    "where_is_my_friends.community_discovery.latest_dynamic"
                  }}</strong>
                {{person.latest_dynamic.excerpt}}
              </a>
            {{/if}}
            <div class="community-discovery__actions">
              {{#if person.primaryTopic}}
                <a
                  class="btn btn-primary"
                  href={{person.primaryTopic.url}}
                  data-test-community-person-primary-action
                  {{on
                    "click"
                    (fn
                      @trackOpen "recommended_user_related_topic_opened" person
                    )
                  }}
                >
                  {{i18n
                    "where_is_my_friends.community_discovery.join_person_discussion"
                  }}
                </a>
              {{/if}}
              <a
                class="btn btn-flat"
                href={{person.profile_url}}
                data-test-community-person-profile-action
                {{on
                  "click"
                  (fn @trackOpen "recommended_user_profile_opened" person)
                }}
              >
                {{i18n "where_is_my_friends.community_discovery.view_profile"}}
              </a>
              {{#if person.invite_url}}
                <a
                  class="btn btn-flat"
                  href={{person.invite_url}}
                  data-test-community-person-invite-action
                  {{on
                    "click"
                    (fn @trackOpen "recommended_user_invite_started" person)
                  }}
                >
                  {{i18n "where_is_my_friends.community_discovery.invite"}}
                </a>
              {{/if}}
              <DButton
                @action={{fn @dismiss "user" person}}
                @label="where_is_my_friends.interests.not_interested"
                @disabled={{@loading}}
                class="btn-flat"
                data-test-community-dismiss
              />
            </div>
          </article>
        {{/each}}
      </div>
    </section>
  </template>
}
