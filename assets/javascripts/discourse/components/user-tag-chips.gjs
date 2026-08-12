import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import UserTagProposeDialog from "./user-tag-propose-dialog";

export default class UserTagChips extends Component {
  @service currentUser;
  @service modal;
  @service siteSettings;

  @tracked tags = [];

  constructor(owner, args) {
    super(owner, args);
    this.tags = this.args.tags ?? [];
  }

  get enabled() {
    return (
      this.siteSettings.where_is_my_friends_enabled &&
      this.siteSettings.where_is_my_friends_user_tags_enabled
    );
  }

  get canPropose() {
    return this.enabled && this.currentUser && this.args.username;
  }

  @action
  openPropose() {
    this.modal.show(UserTagProposeDialog, {
      model: {
        username: this.args.username,
        onProposed: (tag) => this.onProposed(tag),
      },
    });
  }

  @action
  onProposed(tag) {
    const label = tag.label;
    if (!this.tags.some((existing) => existing.label === label)) {
      this.tags = [...this.tags, { id: tag.id, label, endorser_count: 0 }];
    }
  }

  @action
  async toggleEndorse(tag) {
    const type = tag.endorsed_by_me ? "DELETE" : "POST";
    try {
      const response = await ajax(
        `/where-is-my-friends/user-tags/${tag.id}/endorse.json`,
        { type }
      );
      const updated = response.user_tag;
      this.tags = this.tags.map((existing) =>
        existing.id === tag.id
          ? {
              ...existing,
              endorser_count: updated.endorser_count,
              endorsed_by_me: updated.endorsed_by_me,
            }
          : existing
      );
    } catch {
      // Endorsement state is best-effort; keep the previous chip state.
    }
  }

  <template>
    {{#if this.enabled}}
      <div class="where-is-my-friends__user-tags" data-test-user-tags>
        {{#if this.tags.length}}
          <ul class="where-is-my-friends__user-tags-list">
            {{#each this.tags as |tag|}}
              <li
                class="where-is-my-friends__user-tag"
                data-test-user-tag={{tag.label}}
              >
                <span
                  class="where-is-my-friends__user-tag-label"
                >{{tag.label}}</span>
                {{#if this.currentUser}}
                  <DButton
                    @action={{fn this.toggleEndorse tag}}
                    @translatedLabel={{i18n
                      "where_is_my_friends.user_tags.endorse_count"
                      count=tag.endorser_count
                    }}
                    @icon="thumbs-up"
                    class={{if
                      tag.endorsed_by_me
                      "btn-primary btn-small"
                      "btn-flat btn-small"
                    }}
                    data-test-user-tag-endorse={{tag.label}}
                  />
                {{/if}}
              </li>
            {{/each}}
          </ul>
        {{/if}}
        {{#if this.canPropose}}
          <DButton
            @action={{this.openPropose}}
            @label="where_is_my_friends.user_tags.propose"
            @icon="tag"
            class="btn-flat btn-small"
            data-test-user-tag-propose={{@username}}
          />
        {{/if}}
      </div>
    {{/if}}
  </template>
}
