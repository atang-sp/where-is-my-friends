import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class UserTagInbox extends Component {
  @service currentUser;

  @tracked pending = [];
  @tracked managed = [];
  @tracked acceptingUserTags = true;
  @tracked loading = true;
  @tracked saving = false;
  @tracked error = null;

  constructor(owner, args) {
    super(owner, args);
    void this.load();
  }

  get hasPending() {
    return this.pending.length > 0;
  }

  get hasManaged() {
    return this.managed.length > 0;
  }

  @action
  async load() {
    this.loading = true;
    this.error = null;
    try {
      const result = await ajax("/where-is-my-friends/user-tags/mine.json");
      this.pending = result.pending ?? [];
      this.managed = result.managed ?? [];
      this.acceptingUserTags = result.accepting_user_tags;
    } catch {
      this.error = i18n("where_is_my_friends.user_tags.load_error");
    } finally {
      this.loading = false;
    }
  }

  @action
  async respond(tag, actionName) {
    this.saving = true;
    this.error = null;
    try {
      const result = await ajax(
        `/where-is-my-friends/user-tags/${tag.id}/${actionName}.json`,
        { type: "PUT" }
      );
      this.pending = this.pending.filter((t) => t.id !== tag.id);
      this.managed = [result.user_tag, ...this.managed];
    } catch (e) {
      this.error =
        e.jqXHR?.responseJSON?.errors?.join(" ") ||
        i18n("where_is_my_friends.user_tags.errors.generic");
    } finally {
      this.saving = false;
    }
  }

  @action
  async remove(tag) {
    this.saving = true;
    this.error = null;
    try {
      const result = await ajax(
        `/where-is-my-friends/user-tags/${tag.id}/remove.json`,
        { type: "PUT" }
      );
      this.managed = this.managed.map((t) =>
        t.id === tag.id ? result.user_tag : t
      );
    } catch (e) {
      this.error =
        e.jqXHR?.responseJSON?.errors?.join(" ") ||
        i18n("where_is_my_friends.user_tags.errors.generic");
    } finally {
      this.saving = false;
    }
  }

  @action
  async toggleAccepting() {
    this.saving = true;
    this.error = null;
    try {
      const value = !this.acceptingUserTags;
      await ajax(`/u/${this.currentUser.username}.json`, {
        type: "PUT",
        data: {
          user_option: {
            where_is_my_friends_accept_user_tags: value,
          },
        },
      });
      this.acceptingUserTags = value;
    } catch {
      this.error = i18n("where_is_my_friends.user_tags.errors.generic");
    } finally {
      this.saving = false;
    }
  }

  <template>
    <section
      class="where-is-my-friends user-tag-inbox"
      data-test-user-tag-inbox
    >
      <header class="where-is-my-friends__header">
        <p class="where-is-my-friends__eyebrow">{{i18n
            "where_is_my_friends.user_tags.eyebrow"
          }}</p>
        <h1>{{i18n "where_is_my_friends.user_tags.title"}}</h1>
        <p>{{i18n "where_is_my_friends.user_tags.description"}}</p>
      </header>

      {{#if this.error}}
        <div class="alert alert-error" data-test-user-tag-inbox-error>
          {{this.error}}
        </div>
      {{/if}}

      {{#if this.loading}}
        <div class="where-is-my-friends__loading" role="status">
          {{i18n "where_is_my_friends.user_tags.loading"}}
        </div>
      {{else}}
        <section class="user-tag-inbox__accepting" data-test-user-tag-accepting>
          <label>
            <input
              type="checkbox"
              checked={{this.acceptingUserTags}}
              disabled={{this.saving}}
              {{on "change" this.toggleAccepting}}
              data-test-user-tag-accepting-toggle
            />
            {{i18n "where_is_my_friends.user_tags.accepting_toggle"}}
          </label>
        </section>

        <section class="user-tag-inbox__section" data-test-user-tag-pending>
          <h2>{{i18n "where_is_my_friends.user_tags.pending_title"}}</h2>
          {{#if this.hasPending}}
            {{#each this.pending as |tag|}}
              <article
                class="user-tag-inbox__item"
                data-test-user-tag-pending-item={{tag.label}}
              >
                <p>
                  <strong>{{tag.label}}</strong>
                  {{i18n
                    "where_is_my_friends.user_tags.proposed_by"
                    username=tag.proposer.username
                  }}
                </p>
                <div class="user-tag-inbox__actions">
                  <DButton
                    @action={{fn this.respond tag "approve"}}
                    @label="where_is_my_friends.user_tags.approve"
                    @icon="check"
                    @disabled={{this.saving}}
                    class="btn-primary btn-small"
                    data-test-user-tag-approve={{tag.label}}
                  />
                  <DButton
                    @action={{fn this.respond tag "reject"}}
                    @label="where_is_my_friends.user_tags.reject"
                    @icon="xmark"
                    @disabled={{this.saving}}
                    class="btn-flat btn-small"
                    data-test-user-tag-reject={{tag.label}}
                  />
                </div>
              </article>
            {{/each}}
          {{else}}
            <p data-test-user-tag-pending-empty>{{i18n
                "where_is_my_friends.user_tags.pending_empty"
              }}</p>
          {{/if}}
        </section>

        <section class="user-tag-inbox__section" data-test-user-tag-managed>
          <h2>{{i18n "where_is_my_friends.user_tags.managed_title"}}</h2>
          {{#if this.hasManaged}}
            {{#each this.managed as |tag|}}
              <article
                class="user-tag-inbox__item"
                data-test-user-tag-managed-item={{tag.label}}
              >
                <p>
                  <strong>{{tag.label}}</strong>
                  {{i18n
                    (concat "where_is_my_friends.user_tags.status." tag.status)
                  }}
                </p>
                {{#if (eq tag.status "approved")}}
                  <DButton
                    @action={{fn this.remove tag}}
                    @label="where_is_my_friends.user_tags.remove"
                    @icon="trash-can"
                    @disabled={{this.saving}}
                    class="btn-danger btn-small"
                    data-test-user-tag-remove={{tag.label}}
                  />
                {{/if}}
              </article>
            {{/each}}
          {{else}}
            <p data-test-user-tag-managed-empty>{{i18n
                "where_is_my_friends.user_tags.managed_empty"
              }}</p>
          {{/if}}
        </section>
      {{/if}}
    </section>
  </template>
}
