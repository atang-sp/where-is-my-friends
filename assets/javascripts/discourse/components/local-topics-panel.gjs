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
      <a
        class="btn btn-default"
        href={{@actionUrl}}
        aria-label={{i18n "where_is_my_friends.browse_topics_for" city=@city}}
        data-test-local-topics
        data-test-compose-local-topic
        {{on "click" @onAction}}
      >{{this.actionLabel}}</a>
    </section>
  </template>
}
