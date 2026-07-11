import Component from "@glimmer/component";
import PreferenceCheckbox from "discourse/components/preference-checkbox";
import { i18n } from "discourse-i18n";

export default class LocalFriendsNotifications extends Component {
  static shouldRender(_args, { siteSettings }) {
    return siteSettings.where_is_my_friends_enabled;
  }

  <template>
    <div class="control-group local-friends-notifications">
      <label class="control-label">{{i18n "where_is_my_friends.title"}}</label>
      <PreferenceCheckbox
        @labelKey="where_is_my_friends.notify_city_members"
        @checked={{@outletArgs.model.user_option.where_is_my_friends_notify_city}}
        data-setting-name="user-where-is-my-friends-notify-city"
        class="pref-where-is-my-friends-notify-city"
      />
    </div>
  </template>
}
