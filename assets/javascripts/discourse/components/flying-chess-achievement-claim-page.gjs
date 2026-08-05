import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import routeAction from "discourse/helpers/route-action";
import { ajax } from "discourse/lib/ajax";
import { not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

const CLAIM_STORAGE_KEY = "where-is-my-friends-flying-chess-claim-v1";
const MAXIMUM_TOKEN_LENGTH = 4096;

export default class FlyingChessAchievementClaimPage extends Component {
  @service currentUser;
  @service siteSettings;

  @tracked tokenAvailable = false;
  @tracked claiming = false;
  @tracked claimed = false;
  @tracked error = null;
  achievement = null;
  token = null;

  constructor(owner, args) {
    super(owner, args);
    this.captureClaim();
  }

  get enabled() {
    return (
      this.siteSettings.where_is_my_friends_enabled &&
      this.siteSettings.where_is_my_friends_flying_chess_achievements_enabled
    );
  }

  captureClaim() {
    const fragment = new URLSearchParams(window.location.hash.replace(/^#/, ""));
    const incoming = fragment.get("token");
    if (fragment.has("token")) {
      this.token =
        incoming && incoming.length <= MAXIMUM_TOKEN_LENGTH ? incoming : null;
      try {
        if (this.token) {
          sessionStorage.setItem(CLAIM_STORAGE_KEY, this.token);
        } else {
          sessionStorage.removeItem(CLAIM_STORAGE_KEY);
        }
      } catch {
        // The in-memory copy still supports the current page when storage is unavailable.
      }
    } else {
      try {
        this.token = sessionStorage.getItem(CLAIM_STORAGE_KEY);
      } catch {
        this.token = null;
      }
    }
    this.tokenAvailable = Boolean(this.token);
    if (window.location.hash) {
      window.history.replaceState(
        window.history.state,
        "",
        `${window.location.pathname}${window.location.search}`
      );
    }
  }

  @action
  async claim() {
    if (!this.token || this.claiming) {
      return;
    }
    this.claiming = true;
    this.error = null;
    try {
      const response = await ajax(
        "/where-is-my-friends/flying-chess/claims.json",
        { type: "POST", data: { claim_token: this.token } }
      );
      this.achievement = response.achievement;
      this.claimed = true;
      this.tokenAvailable = false;
      this.token = null;
      try {
        sessionStorage.removeItem(CLAIM_STORAGE_KEY);
      } catch {
        // No persistent token was available to remove.
      }
    } catch (error) {
      this.error =
        error?.jqXHR?.responseJSON?.errors?.[0] ??
        i18n("where_is_my_friends.flying_chess.claim_error");
      if ([400, 409, 422].includes(error?.jqXHR?.status)) {
        this.token = null;
        this.tokenAvailable = false;
        try {
          sessionStorage.removeItem(CLAIM_STORAGE_KEY);
        } catch {
          // No persistent token was available to remove.
        }
      }
    } finally {
      this.claiming = false;
    }
  }

  <template>
    <main class="container flying-chess-claim-page">
      <section class="flying-chess-claim-page__card">
        <p class="flying-chess-claim-page__eyebrow">{{i18n
            "where_is_my_friends.flying_chess.eyebrow"
          }}</p>
        <h1>{{i18n "where_is_my_friends.flying_chess.claim_title"}}</h1>

        {{#if this.enabled}}
          {{#if this.claimed}}
            <p class="success">{{i18n
                "where_is_my_friends.flying_chess.claimed"
              }}</p>
            <p>{{i18n
                "where_is_my_friends.flying_chess.completed_games"
                count=this.achievement.completed_games
              }}</p>
          {{else if this.error}}
            <p class="alert alert-error">{{this.error}}</p>
          {{else if (not this.tokenAvailable)}}
            <p>{{i18n "where_is_my_friends.flying_chess.missing_claim"}}</p>
          {{else if (not this.currentUser)}}
            <p>{{i18n
                "where_is_my_friends.flying_chess.login_description"
              }}</p>
            <DButton
              @label="where_is_my_friends.flying_chess.login"
              @action={{routeAction "showLogin"}}
              @icon="user"
              class="btn-primary"
            />
          {{else}}
            <p>{{i18n
                "where_is_my_friends.flying_chess.confirm_description"
              }}</p>
            <p class="flying-chess-claim-page__privacy">{{i18n
                "where_is_my_friends.flying_chess.claim_privacy"
              }}</p>
            <DButton
              @label="where_is_my_friends.flying_chess.confirm"
              @action={{this.claim}}
              @icon="plane"
              @isLoading={{this.claiming}}
              class="btn-primary"
            />
          {{/if}}
        {{else}}
          <p>{{i18n "where_is_my_friends.flying_chess.unavailable"}}</p>
        {{/if}}
      </section>
    </main>
  </template>
}
