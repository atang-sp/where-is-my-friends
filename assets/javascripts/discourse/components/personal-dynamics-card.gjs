import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { trustHTML } from "@ember/template";
import DDecoratedHtml from "discourse/ui-kit/d-decorated-html";
import DRelativeDate from "discourse/ui-kit/d-relative-date";
import { i18n } from "discourse-i18n";

export default class PersonalDynamicsCard extends Component {
  get cooked() {
    return trustHTML(this.args.dynamic.cooked ?? "");
  }

  get authorName() {
    return (
      this.args.dynamic.author?.name ?? this.args.dynamic.author?.username ?? ""
    );
  }

  <template>
    <article
      class="personal-dynamics__card"
      data-test-personal-dynamic={{@dynamic.id}}
    >
      {{#if @showAuthor}}
        <header class="personal-dynamics__author">
          <a
            href={{@dynamic.author.dynamics_url}}
            data-test-personal-dynamic-author
          >{{this.authorName}}</a>
          <span>@{{@dynamic.author.username}}</span>
        </header>
      {{/if}}
      <DDecoratedHtml
        @html={{this.cooked}}
        @className={{if
          @compact
          "personal-dynamics__cooked personal-dynamics__cooked--compact"
          "personal-dynamics__cooked"
        }}
      />
      <footer class="personal-dynamics__meta">
        <span><DRelativeDate @date={{@dynamic.created_at}} /></span>
        <span>{{i18n
            "where_is_my_friends.dynamics.reply_count"
            count=@dynamic.reply_count
          }}</span>
        <a
          href={{@dynamic.url}}
          data-test-personal-dynamic-open
          {{on "click" @onOpen}}
        >{{i18n "where_is_my_friends.dynamics.open_and_reply"}}</a>
      </footer>
    </article>
  </template>
}
