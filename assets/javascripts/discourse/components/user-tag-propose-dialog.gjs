import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";

const PRESET_GROUPS = Object.freeze([
  {
    key: "practice",
    titleKey: "where_is_my_friends.user_tags.preset_groups.practice",
    tags: ["手法温和", "严格守信", "注重沟通", "Aftercare细致", "情绪稳定"],
  },
  {
    key: "personality",
    titleKey: "where_is_my_friends.user_tags.preset_groups.personality",
    tags: ["温柔体贴", "谈吐文雅", "靠谱真诚", "幽默风趣", "善于倾听"],
  },
  {
    key: "community",
    titleKey: "where_is_my_friends.user_tags.preset_groups.community",
    tags: ["小说大触", "棋力高超", "干货满满", "理论扎实", "安全意识高"],
  },
]);

export default class UserTagProposeDialog extends Component {
  @service siteSettings;

  presetGroups = PRESET_GROUPS;

  @tracked label = "";
  @tracked submitting = false;
  @tracked error = null;

  get maxLength() {
    return this.siteSettings.where_is_my_friends_user_tag_max_length || 20;
  }

  get canSubmit() {
    const trimmed = this.label.trim();
    return trimmed.length > 0 && trimmed.length <= this.maxLength;
  }

  get characterCountLabel() {
    return i18n("where_is_my_friends.user_tags.character_count", {
      count: this.label.length,
      max: this.maxLength,
    });
  }

  @action
  selectPreset(tag) {
    if (this.label.trim() === tag) {
      this.label = "";
    } else {
      this.label = tag;
    }
  }

  @action
  updateLabel(event) {
    this.label = event.target.value;
  }

  @action
  async submit() {
    if (!this.canSubmit || this.submitting) {
      return;
    }

    this.submitting = true;
    this.error = null;
    try {
      const response = await ajax("/where-is-my-friends/user-tags.json", {
        type: "POST",
        data: {
          username: this.args.model.username,
          label: this.label.trim(),
        },
      });
      this.args.model.onProposed(response.user_tag);
      this.args.closeModal();
    } catch (e) {
      this.error =
        e.jqXHR?.responseJSON?.errors?.join(" ") ||
        i18n("where_is_my_friends.user_tags.errors.generic");
    } finally {
      this.submitting = false;
    }
  }

  <template>
    <DModal
      @title={{i18n
        "where_is_my_friends.user_tags.propose_title"
        username=@model.username
      }}
      @closeModal={{@closeModal}}
      class="where-is-my-friends-user-tag-propose-modal"
    >
      <:body>
        <p>{{i18n
            "where_is_my_friends.user_tags.propose_description"
            username=@model.username
          }}</p>
        <input
          type="text"
          class="where-is-my-friends__user-tag-input"
          value={{this.label}}
          maxlength={{this.maxLength}}
          placeholder={{i18n
            "where_is_my_friends.user_tags.propose_placeholder"
          }}
          aria-label={{i18n
            "where_is_my_friends.user_tags.propose_placeholder"
          }}
          data-test-user-tag-input
          {{on "input" this.updateLabel}}
        />
        <span class="where-is-my-friends__user-tag-count">
          {{this.characterCountLabel}}
        </span>
        <div
          class="where-is-my-friends__user-tag-presets"
          data-test-user-tag-presets
        >
          <span class="where-is-my-friends__user-tag-presets-title">
            {{i18n "where_is_my_friends.user_tags.preset_title"}}
          </span>
          <div class="where-is-my-friends__user-tag-preset-groups">
            {{#each this.presetGroups as |group|}}
              <div class="where-is-my-friends__user-tag-preset-group">
                <span class="where-is-my-friends__user-tag-preset-group-title">
                  {{i18n group.titleKey}}
                </span>
                <div class="where-is-my-friends__user-tag-preset-chips">
                  {{#each group.tags as |tag|}}
                    <button
                      type="button"
                      class="btn btn-default btn-small where-is-my-friends__preset-chip {{if (eq this.label tag) 'is-selected'}}"
                      data-test-user-tag-preset-chip={{tag}}
                      {{on "click" (fn this.selectPreset tag)}}
                    >
                      {{tag}}
                    </button>
                  {{/each}}
                </div>
              </div>
            {{/each}}
          </div>
        </div>
        {{#if this.error}}
          <p
            class="alert alert-error"
            data-test-user-tag-error
          >{{this.error}}</p>
        {{/if}}
      </:body>
      <:footer>
        <DButton
          @action={{this.submit}}
          @label="where_is_my_friends.user_tags.propose"
          @icon="tag"
          @disabled={{not this.canSubmit}}
          @isLoading={{this.submitting}}
          class="btn-primary"
          data-test-user-tag-propose-submit
        />
        <DButton
          @action={{@closeModal}}
          @label="where_is_my_friends.user_tags.cancel"
          class="btn-flat"
          data-test-user-tag-propose-cancel
        />
      </:footer>
    </DModal>
  </template>
}
