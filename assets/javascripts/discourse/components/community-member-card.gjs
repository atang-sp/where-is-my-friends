import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { LinkTo } from "@ember/routing";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import { i18n } from "discourse-i18n";
import UserTagChips from "./user-tag-chips";

export default class CommunityMemberCard extends Component {
  hasAvatarFrame = (user) => {
    const lvl = user?.community_level?.level;
    return typeof lvl === "number" && lvl >= 2 && lvl <= 8;
  };

  isLevel7 = (user) => {
    return user?.community_level?.level === 7;
  };

  isLevel8 = (user) => {
    return user?.community_level?.level === 8;
  };

  pillModifier = (user) => {
    const lvl = user?.community_level?.level;
    if (lvl >= 7) {
      return "community-avatar-frame__pill--legend";
    }
    if (lvl >= 5) {
      return "community-avatar-frame__pill--high";
    }
    return "";
  };

  roleBadge = (user) => {
    const key = user?.role_key;
    if (!key) {
      return null;
    }
    const map = {
      active_role: {
        labelKey: "where_is_my_friends.roles.active.label",
        titleKey: "where_is_my_friends.roles.active.title",
        key: "active_role",
      },
      passive_role: {
        labelKey: "where_is_my_friends.roles.passive.label",
        titleKey: "where_is_my_friends.roles.passive.title",
        key: "passive_role",
      },
      switch_role: {
        labelKey: "where_is_my_friends.roles.switch.label",
        titleKey: "where_is_my_friends.roles.switch.title",
        key: "switch_role",
      },
    };
    return map[key] || null;
  };

  hasRoleBadge = (user) => {
    return Boolean(this.roleBadge(user));
  };

  roleBadgeClass = (user) => {
    const info = this.roleBadge(user);
    return info ? `role-${info.key}` : "";
  };

  roleBadgeLabel = (user) => {
    const key = this.roleBadge(user)?.labelKey;
    return key ? i18n(key) : "";
  };

  roleBadgeTitle = (user) => {
    const key = this.roleBadge(user)?.titleKey;
    return key ? i18n(key) : "";
  };

  <template>
    <article
      class="where-is-my-friends__user-card"
      data-test-user-card={{@user.username}}
    >
      {{#if @user.avatar_template}}
        <div class="where-is-my-friends__avatar-wrapper">
          {{dAvatar @user imageSize="large"}}
          {{#if (this.hasAvatarFrame @user)}}
            <div
              class="community-avatar-frame community-avatar-frame--level-{{@user.community_level.level}}"
              aria-hidden="true"
            >
              <span class="community-avatar-frame__ring"></span>
              {{#if (this.isLevel7 @user)}}
                <span class="community-avatar-frame__wing-left"></span>
                <span class="community-avatar-frame__wing-right"></span>
              {{/if}}
              {{#if (this.isLevel8 @user)}}
                <span class="community-avatar-frame__wing-grand-left"></span>
                <span class="community-avatar-frame__wing-grand-right"></span>
                <span class="community-avatar-frame__crown"></span>
              {{/if}}
              <span
                class="community-avatar-frame__pill {{this.pillModifier @user}}"
                title="Lv.{{@user.community_level.level}}"
              >
                Lv.{{@user.community_level.level}}
              </span>
              {{#if (this.hasRoleBadge @user)}}
                <span
                  class="community-avatar-frame__role
                    {{this.roleBadgeClass @user}}"
                  title={{this.roleBadgeTitle @user}}
                >
                  {{this.roleBadgeLabel @user}}
                </span>
              {{/if}}
            </div>
          {{/if}}
        </div>
      {{/if}}
      <div>
        <h3>
          {{if @user.name @user.name @user.username}}
          {{#if @user.is_recent}}
            <span
              class="where-is-my-friends__new-badge"
              data-test-new-member-badge
            >{{i18n "where_is_my_friends.new_member_badge"}}</span>
          {{/if}}
        </h3>
        <LinkTo @route="user" @model={{@user.username}}>
          @{{@user.username}}
        </LinkTo>
        <p>{{@user.city}}{{#if @user.distance_label}}
            ·
            {{@user.distance_label}}{{/if}}</p>
        {{#if @user.activity_label}}
          <p
            class={{if
              @user.online
              "where-is-my-friends__activity is-online"
              "where-is-my-friends__activity"
            }}
            data-test-user-activity
          >{{@user.activity_label}}</p>
        {{/if}}
        {{#if @user.custom_field_label}}
          <p>
            <span
              class="where-is-my-friends__user-attrs"
              data-test-user-attrs
            >{{@user.custom_field_label}}</span>
          </p>
        {{/if}}
        <UserTagChips @username={{@user.username}} @tags={{@user.user_tags}} />
        {{#if @user.inactive}}
          {{#unless @user.activity_label}}
            <p
              class="where-is-my-friends__inactive"
              data-test-inactive-member
            >{{i18n "where_is_my_friends.inactive_member"}}</p>
          {{/unless}}
        {{/if}}
        {{#if @user.bio_excerpt}}
          <p
            class="where-is-my-friends__bio"
            data-test-user-bio
          >{{@user.bio_excerpt}}</p>
        {{/if}}
      </div>
      <div class="where-is-my-friends__user-actions">
        <LinkTo
          @route="user"
          @model={{@user.username}}
          class="btn"
          aria-label={{i18n
            "where_is_my_friends.view_profile_for"
            username=@user.username
          }}
          data-test-profile-link={{@user.username}}
          {{on "click" (fn @onConnect "profile_clicked")}}
        >{{i18n "where_is_my_friends.view_profile"}}</LinkTo>
        {{#if @user.action_url}}
          <a
            class="btn"
            href={{@user.action_url}}
            aria-label={{i18n
              "where_is_my_friends.message_user"
              username=@user.username
            }}
            data-test-message-link={{@user.username}}
            {{on "click" (fn @onConnect "message_started")}}
          >{{i18n
              (if
                @chatEnabled
                "where_is_my_friends.start_chat"
                "where_is_my_friends.send_message"
              )
            }}</a>
        {{/if}}
      </div>
    </article>
  </template>
}
