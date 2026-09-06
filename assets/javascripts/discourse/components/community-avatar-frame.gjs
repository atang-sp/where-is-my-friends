import Component from "@glimmer/component";
import { service } from "@ember/service";

const ROLE_MAP = {
  active: { label: "主", key: "active_role", title: "角色：主" },
  active_role: { label: "主", key: "active_role", title: "角色：主" },
  主动: { label: "主", key: "active_role", title: "角色：主" },
  主: { label: "主", key: "active_role", title: "角色：主" },
  passive: { label: "被", key: "passive_role", title: "角色：被" },
  passive_role: { label: "被", key: "passive_role", title: "角色：被" },
  被动: { label: "被", key: "passive_role", title: "角色：被" },
  被: { label: "被", key: "passive_role", title: "角色：被" },
  switch: { label: "双", key: "switch_role", title: "角色：双" },
  switch_role: { label: "双", key: "switch_role", title: "角色：双" },
  双向: { label: "双", key: "switch_role", title: "角色：双" },
  双: { label: "双", key: "switch_role", title: "角色：双" },
};

export default class CommunityAvatarFrame extends Component {
  @service siteSettings;

  get enabled() {
    if (
      this.siteSettings?.where_is_my_friends_avatar_frames_enabled === false
    ) {
      return false;
    }
    return true;
  }

  get levelNumber() {
    const raw =
      this.args.level ||
      this.args.post?.community_level ||
      this.args.user?.community_level ||
      this.args.model?.community_level;
    if (!raw) {
      return 0;
    }
    if (typeof raw === "number") {
      return raw;
    }
    if (typeof raw === "object" && raw.level) {
      return Number(raw.level) || 0;
    }
    return Number(raw) || 0;
  }

  get isVisible() {
    // Level 1 has NO frame per user requirement
    return this.enabled && this.levelNumber >= 2 && this.levelNumber <= 8;
  }

  get isLevel7() {
    return this.levelNumber === 7;
  }

  get isLevel8() {
    return this.levelNumber === 8;
  }

  get showPill() {
    if (this.args.showPill === false) {
      return false;
    }
    return (
      this.siteSettings?.where_is_my_friends_avatar_frames_show_pill !== false
    );
  }

  get pillModifier() {
    if (this.levelNumber >= 7) {
      return "community-avatar-frame__pill--legend";
    }
    if (this.levelNumber >= 5) {
      return "community-avatar-frame__pill--high";
    }
    return "";
  }

  get roleInfo() {
    const role =
      this.args.role ||
      this.args.post?.role_key ||
      this.args.post?.user_custom_fields?.interaction_role ||
      this.args.user?.role_key ||
      this.args.user?.user_fields?.interaction_role ||
      this.args.user?.user_fields?.["1"] ||
      this.args.user?.custom_fields?.["user_field_1"] ||
      this.args.model?.role_key ||
      this.args.model?.user_fields?.interaction_role ||
      this.args.model?.user_fields?.["1"] ||
      this.args.model?.custom_fields?.["user_field_1"];
    if (!role) {
      return null;
    }
    return ROLE_MAP[role] || null;
  }

  <template>
    {{#if this.isVisible}}
      <div
        class="community-avatar-frame community-avatar-frame--level-{{this.levelNumber}}"
        ...attributes
      >
        <span class="community-avatar-frame__ring" aria-hidden="true"></span>

        {{#if this.isLevel7}}
          <span
            class="community-avatar-frame__wing-left"
            aria-hidden="true"
          ></span>
          <span
            class="community-avatar-frame__wing-right"
            aria-hidden="true"
          ></span>
        {{/if}}

        {{#if this.isLevel8}}
          <span
            class="community-avatar-frame__wing-grand-left"
            aria-hidden="true"
          ></span>
          <span
            class="community-avatar-frame__wing-grand-right"
            aria-hidden="true"
          ></span>
          <span class="community-avatar-frame__crown" aria-hidden="true"></span>
        {{/if}}

        {{#if this.showPill}}
          <span
            class="community-avatar-frame__pill {{this.pillModifier}}"
            title="Lv.{{this.levelNumber}}"
          >
            Lv.{{this.levelNumber}}
          </span>
        {{/if}}

        {{#if this.roleInfo}}
          <span
            class="community-avatar-frame__role role-{{this.roleInfo.key}}"
            title={{this.roleInfo.title}}
          >
            {{this.roleInfo.label}}
          </span>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
