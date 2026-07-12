import Component from "@glimmer/component";
import { LinkTo } from "@ember/routing";
import { i18n } from "discourse-i18n";

export default class LocalFriendsProfile extends Component {
  static shouldRender(_args, { siteSettings }) {
    return siteSettings.where_is_my_friends_enabled;
  }

  get city() {
    return this.args.outletArgs?.model?.where_is_my_friends_city;
  }

  <template>
    {{#if this.city}}
      <div class="local-friends-profile-city">
        <LinkTo
          @route="where-is-my-friends"
          class="local-friends-profile-city__link"
          title={{i18n "where_is_my_friends.user_card_city_title" city=this.city}}
        >
          {{this.city}}
        </LinkTo>
      </div>
    {{/if}}
  </template>
}
