import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class FlyingChessProfile extends Component {
  static shouldRender(args, { siteSettings }) {
    return (
      siteSettings.where_is_my_friends_enabled &&
      siteSettings.where_is_my_friends_flying_chess_achievements_enabled &&
      Boolean(args.outletArgs?.model?.where_is_my_friends_flying_chess)
    );
  }

  @service siteSettings;

  @tracked
  achievement = this.args.outletArgs?.model?.where_is_my_friends_flying_chess;
  @tracked saving = false;
  @tracked error = null;

  get gameUrl() {
    return this.siteSettings.where_is_my_friends_flying_chess_game_url;
  }

  @action
  async toggleVisibility() {
    if (!this.achievement?.can_manage || this.saving) {
      return;
    }
    this.saving = true;
    this.error = null;
    try {
      const response = await ajax(
        "/where-is-my-friends/flying-chess/profile.json",
        {
          type: "PUT",
          data: { profile_visible: !this.achievement.profile_visible },
        }
      );
      this.achievement = response.achievement;
    } catch (error) {
      this.error =
        error?.jqXHR?.responseJSON?.errors?.[0] ??
        i18n("where_is_my_friends.flying_chess.profile_update_error");
    } finally {
      this.saving = false;
    }
  }

  <template>
    <section class="flying-chess-profile" data-test-flying-chess-profile>
      <div>
        <p class="flying-chess-profile__eyebrow">{{i18n
            "where_is_my_friends.flying_chess.profile_eyebrow"
          }}</p>
        <h3>{{i18n "where_is_my_friends.flying_chess.profile_title"}}</h3>
        <p>{{i18n
            "where_is_my_friends.flying_chess.completed_games"
            count=this.achievement.completed_games
          }}</p>
        <span
          class="flying-chess-profile__badge"
        >{{this.achievement.badge_name}}</span>
        {{#if this.achievement.can_manage}}
          <p class="flying-chess-profile__privacy">{{if
              this.achievement.profile_visible
              (i18n "where_is_my_friends.flying_chess.profile_public")
              (i18n "where_is_my_friends.flying_chess.profile_private")
            }}</p>
          {{#if this.error}}
            <p class="alert alert-error">{{this.error}}</p>
          {{/if}}
        {{/if}}
      </div>
      <div class="flying-chess-profile__actions">
        <a
          class="btn btn-primary"
          href={{this.gameUrl}}
          rel="noopener noreferrer"
          data-test-start-flying-chess
        >{{i18n "where_is_my_friends.flying_chess.start_game"}}</a>
        {{#if this.achievement.can_manage}}
          <DButton
            @label={{if
              this.achievement.profile_visible
              "where_is_my_friends.flying_chess.hide_profile"
              "where_is_my_friends.flying_chess.show_profile"
            }}
            @action={{this.toggleVisibility}}
            @isLoading={{this.saving}}
            class="btn-default"
          />
        {{/if}}
      </div>
    </section>
  </template>
}
