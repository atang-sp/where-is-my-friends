import Component from "@glimmer/component";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export default class PersonalDynamicsTab extends Component {
  @service currentUser;
  @service siteSettings;

  get visible() {
    return (
      this.currentUser &&
      this.siteSettings.where_is_my_friends_enabled &&
      this.siteSettings.where_is_my_friends_dynamics_enabled
    );
  }

  <template>
    {{#if this.visible}}
      <li class="user-activity-bottom-outlet personal-dynamics-tab">
        <LinkTo @route="userActivity.dynamics">
          {{dIcon "message"}}
          {{i18n "where_is_my_friends.dynamics.tab"}}
        </LinkTo>
      </li>
    {{/if}}
  </template>
}
