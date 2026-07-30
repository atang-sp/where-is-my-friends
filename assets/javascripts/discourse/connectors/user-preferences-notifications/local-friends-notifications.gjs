import Component from "@glimmer/component";
import { service } from "@ember/service";
import PreferenceCheckbox from "discourse/components/preference-checkbox";
import { i18n } from "discourse-i18n";

export default class LocalFriendsNotifications extends Component {
  static shouldRender(_args, { siteSettings }) {
    return siteSettings.where_is_my_friends_enabled;
  }

  @service siteSettings;

  <template>
    <div class="control-group local-friends-notifications">
      <label class="control-label">{{i18n "where_is_my_friends.title"}}</label>
      <PreferenceCheckbox
        @labelKey="where_is_my_friends.notify_city_members"
        @checked={{@outletArgs.model.user_option.where_is_my_friends_notify_city}}
        data-setting-name="user-where-is-my-friends-notify-city"
        class="pref-where-is-my-friends-notify-city"
      />
      <PreferenceCheckbox
        @labelKey="where_is_my_friends.notify_nearby_members"
        @checked={{@outletArgs.model.user_option.where_is_my_friends_notify_nearby}}
        data-setting-name="user-where-is-my-friends-notify-nearby"
        class="pref-where-is-my-friends-notify-nearby"
      />
      {{#if this.siteSettings.where_is_my_friends_practice_invitations_enabled}}
        <PreferenceCheckbox
          @labelKey="where_is_my_friends.practice_invitations.accept_setting"
          @checked={{@outletArgs.model.user_option.where_is_my_friends_accept_practice_invitations}}
          data-setting-name="user-where-is-my-friends-accept-practice-invitations"
          class="pref-where-is-my-friends-accept-practice-invitations"
        />
      {{/if}}
    </div>
  </template>
}
