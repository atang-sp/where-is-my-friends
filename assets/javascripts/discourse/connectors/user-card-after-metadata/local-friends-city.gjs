import Component from "@glimmer/component";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { or } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

export default class LocalFriendsCity extends Component {
  static shouldRender(_args, { siteSettings }) {
    return siteSettings.where_is_my_friends_enabled;
  }

  @service siteSettings;

  get city() {
    return this.args.outletArgs?.user?.where_is_my_friends_city;
  }

  get publicInterests() {
    return (
      this.args.outletArgs?.user?.where_is_my_friends_public_interests ?? []
    );
  }

  get invitationInterests() {
    return (
      this.args.outletArgs?.user
        ?.where_is_my_friends_practice_invitation_interests ?? []
    );
  }

  get inviteHref() {
    const username = this.args.outletArgs?.user?.username;
    return `/where-is-my-friends/interests?invite_to=${encodeURIComponent(
      username
    )}`;
  }

  <template>
    {{#if (or this.city this.publicInterests.length)}}
      <div class="local-friends-city-badge">
        {{#if this.city}}
          <LinkTo
            @route="where-is-my-friends"
            class="local-friends-city-badge__link"
            title={{i18n
              "where_is_my_friends.user_card_city_title"
              city=this.city
            }}
          >
            {{this.city}}
          </LinkTo>
        {{/if}}
        {{#if this.publicInterests.length}}
          <div class="local-friends-public-interests">
            <span>{{i18n
                "where_is_my_friends.interests.public_profile_title"
              }}</span>
            {{#each this.publicInterests as |interest|}}
              <span class="local-friends-public-interests__tag">
                {{interest.name}}
              </span>
            {{/each}}
          </div>
        {{/if}}
        {{#if
          this.siteSettings.where_is_my_friends_practice_invitations_enabled
        }}
          {{#if this.invitationInterests.length}}
            <a
              href={{this.inviteHref}}
              class="btn btn-primary btn-small local-friends-practice-invite"
              data-test-card-practice-invite
            >
              {{i18n "where_is_my_friends.practice_invitations.invite"}}
            </a>
          {{/if}}
        {{/if}}
      </div>
    {{/if}}
  </template>
}
