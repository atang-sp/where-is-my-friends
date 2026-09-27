import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class CommunityDiscoveryInterests extends Component {
  <template>
    <section class="community-discovery__section">
      <h3>{{i18n
          "where_is_my_friends.community_discovery.interests_title"
        }}</h3>
      <div
        class="community-discovery__grid community-discovery__grid--interests"
      >
        {{#each @interests as |interest|}}
          <article data-test-community-interest={{interest.id}}>
            <a
              href={{interest.url}}
              data-test-community-interest-action
              {{on
                "click"
                (fn @trackOpen "recommended_interest_opened" interest)
              }}
            >
              <h4>{{interest.name}}</h4>
            </a>
            <p data-test-community-interest-reason>
              <strong>{{i18n
                  "where_is_my_friends.community_discovery.why"
                }}</strong>
              {{#if interest.reason_interest}}
                {{i18n
                  "where_is_my_friends.community_discovery.exploration_reason"
                  from=interest.reason_interest.name
                  to=interest.name
                }}
              {{else}}
                {{#if interest.active_member_count_suppressed}}
                  {{i18n
                    "where_is_my_friends.community_discovery.interest_reason_private"
                    topicCount=interest.topic_count
                    newCount=interest.new_topic_count
                  }}
                {{else}}
                  {{i18n
                    "where_is_my_friends.community_discovery.interest_reason"
                    topicCount=interest.topic_count
                    newCount=interest.new_topic_count
                    memberCount=interest.active_member_count
                  }}
                {{/if}}
              {{/if}}
            </p>
            <div class="community-discovery__actions">
              <a
                class="btn btn-primary"
                href={{interest.url}}
                {{on
                  "click"
                  (fn @trackOpen "recommended_interest_opened" interest)
                }}
              >
                {{i18n "where_is_my_friends.community_discovery.explore"}}
              </a>
              <DButton
                @action={{fn @dismiss "interest" interest}}
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
