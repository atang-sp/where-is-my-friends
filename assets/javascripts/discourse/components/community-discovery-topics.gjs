import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { concat } from "@ember/helper";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class CommunityDiscoveryTopics extends Component {
  <template>
    <section class="community-discovery__section">
      <h3>{{i18n "where_is_my_friends.community_discovery.topics_title"}}</h3>
      <div class="community-discovery__grid">
        {{#each @topics as |topic|}}
          <article data-test-community-topic={{topic.id}}>
            <a
              href={{topic.url}}
              data-test-community-topic-action
              {{on "click" (fn @trackOpen "recommended_topic_opened" topic)}}
            >
              <h4>{{topic.fancy_title}}</h4>
            </a>
            <p data-test-community-topic-reason>
              <strong>{{i18n
                  "where_is_my_friends.community_discovery.why"
                }}</strong>
              {{i18n "where_is_my_friends.community_discovery.topic_reason"}}
              {{#each topic.matching_interests as |interest|}}
                <span>{{interest.name}}</span>
              {{/each}}
            </p>
            <p class="community-discovery__signal">
              {{i18n
                (concat
                  "where_is_my_friends.community_discovery.topic_state."
                  topic.participation_state
                )
              }}
            </p>
            <div class="community-discovery__actions">
              <a
                class="btn btn-primary"
                href={{topic.url}}
                {{on "click" (fn @trackOpen "recommended_topic_opened" topic)}}
              >
                {{i18n
                  "where_is_my_friends.community_discovery.join_discussion"
                }}
              </a>
              <DButton
                @action={{fn @dismiss "topic" topic}}
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
