import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";

export default class LocalTopicsPanel extends Component {
  get actionLabel() {
    return this.args.compose
      ? i18n("where_is_my_friends.start_local_topic")
      : i18n("where_is_my_friends.browse_local_topics");
  }

  <template>
    <section
      class="where-is-my-friends__local-topics"
      data-test-local-topics-panel
    >
      <div class="where-is-my-friends__local-topics-heading">
        <div>
          <h3>{{i18n "where_is_my_friends.local_topics_title"}}</h3>
          <p>{{i18n "where_is_my_friends.local_topics_description"}}</p>
        </div>
        <a
          class="btn btn-primary"
          href={{@actionUrl}}
          aria-label={{i18n "where_is_my_friends.browse_topics_for" city=@city}}
          data-test-local-topics
          data-test-compose-local-topic
          {{on "click" @onCompose}}
        >{{this.actionLabel}}</a>
      </div>

      {{#if @topics.length}}
        <div class="where-is-my-friends__local-topic-list">
          {{#each @topics as |topic|}}
            <a
              href={{topic.url}}
              class="where-is-my-friends__local-topic"
              data-test-local-topic={{topic.id}}
              {{on "click" @onOpen}}
            >
              <strong>{{topic.title}}</strong>
              <span>{{i18n
                  "where_is_my_friends.local_topic_meta"
                  city=topic.activity_city
                  posts=topic.posts_count
                }}</span>
            </a>
          {{/each}}
        </div>
      {{else}}
        <p class="where-is-my-friends__local-topics-empty">{{i18n
            "where_is_my_friends.local_topics_empty"
          }}</p>
      {{/if}}
    </section>
  </template>
}
