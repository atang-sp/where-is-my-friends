import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trustHTML } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import DDecoratedHtml from "discourse/ui-kit/d-decorated-html";
import DRelativeDate from "discourse/ui-kit/d-relative-date";
import { i18n } from "discourse-i18n";

export default class PersonalDynamicsCard extends Component {
  @tracked reaction = this.args.dynamic.reaction ?? null;
  @tracked reactionSaving = false;
  @tracked reactionError = null;

  get cooked() {
    return trustHTML(this.args.dynamic.cooked ?? "");
  }

  get authorName() {
    return (
      this.args.dynamic.author?.name ?? this.args.dynamic.author?.username ?? ""
    );
  }

  get canReact() {
    return Boolean(this.args.dynamic.can_react);
  }

  get relateSelected() {
    return this.reaction === "relate";
  }

  get curiousSelected() {
    return this.reaction === "curious";
  }

  get openToChatSelected() {
    return this.reaction === "open_to_chat";
  }

  get supportSelected() {
    return this.reaction === "support";
  }

  @action
  async toggleReaction(kind) {
    if (this.reactionSaving) {
      return;
    }

    this.reactionSaving = true;
    this.reactionError = null;
    const removing = this.reaction === kind;
    try {
      const result = await ajax(
        `/where-is-my-friends/dynamics/${this.args.dynamic.id}/reaction.json`,
        removing ? { type: "DELETE" } : { type: "POST", data: { kind } }
      );
      this.reaction = result.reaction ?? null;
    } catch (error) {
      this.reactionError =
        error?.jqXHR?.responseJSON?.errors?.[0] ??
        i18n("where_is_my_friends.dynamics.reaction_error");
    } finally {
      this.reactionSaving = false;
    }
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
      {{#if this.canReact}}
        <div
          class="personal-dynamics__reactions"
          role="group"
          aria-label={{i18n "where_is_my_friends.dynamics.reactions_label"}}
          data-test-personal-dynamic-reactions
        >
          <DButton
            @action={{fn this.toggleReaction "relate"}}
            @label="where_is_my_friends.dynamics.reactions.relate"
            @disabled={{this.reactionSaving}}
            class={{if
              this.relateSelected
              "btn-flat personal-dynamics__reaction is-active"
              "btn-flat personal-dynamics__reaction"
            }}
            aria-pressed={{this.relateSelected}}
            data-test-dynamic-reaction="relate"
          />
          <DButton
            @action={{fn this.toggleReaction "curious"}}
            @label="where_is_my_friends.dynamics.reactions.curious"
            @disabled={{this.reactionSaving}}
            class={{if
              this.curiousSelected
              "btn-flat personal-dynamics__reaction is-active"
              "btn-flat personal-dynamics__reaction"
            }}
            aria-pressed={{this.curiousSelected}}
            data-test-dynamic-reaction="curious"
          />
          <DButton
            @action={{fn this.toggleReaction "open_to_chat"}}
            @label="where_is_my_friends.dynamics.reactions.open_to_chat"
            @disabled={{this.reactionSaving}}
            class={{if
              this.openToChatSelected
              "btn-flat personal-dynamics__reaction is-active"
              "btn-flat personal-dynamics__reaction"
            }}
            aria-pressed={{this.openToChatSelected}}
            data-test-dynamic-reaction="open_to_chat"
          />
          <DButton
            @action={{fn this.toggleReaction "support"}}
            @label="where_is_my_friends.dynamics.reactions.support"
            @disabled={{this.reactionSaving}}
            class={{if
              this.supportSelected
              "btn-flat personal-dynamics__reaction is-active"
              "btn-flat personal-dynamics__reaction"
            }}
            aria-pressed={{this.supportSelected}}
            data-test-dynamic-reaction="support"
          />
        </div>
        {{#if this.reactionError}}
          <p
            class="personal-dynamics__reaction-error"
            role="alert"
            data-test-dynamic-reaction-error
          >{{this.reactionError}}</p>
        {{/if}}
      {{/if}}
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
