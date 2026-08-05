import Component from "@glimmer/component";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { i18n } from "discourse-i18n";

const COMPOSER_CLASS = "where-is-my-friends-dynamic-composer";

export default class DynamicReplyMediaGuard extends Component {
  replyControl = null;

  get visible() {
    const model = this.args.outletArgs?.model;
    return Boolean(
      model?.topic?.where_is_my_friends_dynamic ||
      model?.where_is_my_friends_dynamic
    );
  }

  @action
  markComposer(element) {
    if (!this.visible) {
      return;
    }

    this.replyControl = element.closest("#reply-control");
    this.replyControl?.classList.add(COMPOSER_CLASS);
  }

  @action
  unmarkComposer() {
    this.replyControl?.classList.remove(COMPOSER_CLASS);
    this.replyControl = null;
  }

  <template>
    {{#if this.visible}}
      <p
        class="dynamic-reply-media-guard"
        data-test-dynamic-reply-media-guard
        {{didInsert this.markComposer}}
        {{willDestroy this.unmarkComposer}}
      >{{i18n "where_is_my_friends.dynamics.reply_media_guidance"}}</p>
    {{/if}}
  </template>
}
