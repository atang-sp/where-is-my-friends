import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const DISMISSED_KEY = "local-friends-composer-hint-dismissed";

export default class LocalFriendsComposerHint extends Component {
  @service currentUser;
  @service siteSettings;

  @tracked visible = false;
  @tracked userCity = null;

  get targetCategorySlug() {
    return this.siteSettings.where_is_my_friends_target_category_slug?.trim();
  }

  get isTargetCategory() {
    if (!this.targetCategorySlug) {
      return false;
    }
    const category = this.args.outletArgs?.model?.category;
    return category?.slug === this.targetCategorySlug;
  }

  get shouldCheck() {
    if (!this.currentUser) {
      return false;
    }
    if (!this.siteSettings.where_is_my_friends_enabled) {
      return false;
    }
    if (!this.isTargetCategory) {
      return false;
    }
    try {
      const dismissed = sessionStorage.getItem(DISMISSED_KEY);
      if (dismissed && Date.now() - Number(dismissed) < 7 * 86400000) {
        return false;
      }
    } catch {
      // ignore
    }
    return true;
  }

  get hintText() {
    if (this.userCity) {
      return i18n("where_is_my_friends.composer_hint", {
        city: this.userCity,
      });
    }
    return i18n("where_is_my_friends.composer_hint_no_city");
  }

  @action
  async checkStatus() {
    if (!this.shouldCheck) {
      return;
    }

    try {
      const data = await ajax("/where-is-my-friends.json");
      if (!data.location) {
        this.userCity = data.profile_location || null;
        this.visible = true;
      }
    } catch {
      // silent
    }
  }

  @action
  dismiss() {
    this.visible = false;
    try {
      sessionStorage.setItem(DISMISSED_KEY, String(Date.now()));
    } catch {
      // ignore
    }
  }

  <template>
    <span hidden {{didInsert this.checkStatus}}></span>
    {{#if this.visible}}
      <div class="local-friends-composer-hint" data-test-composer-hint>
        <span class="local-friends-composer-hint__text">{{this.hintText}}</span>
        <LinkTo
          @route="where-is-my-friends"
          class="btn btn-small btn-primary local-friends-composer-hint__cta"
        >
          {{i18n "where_is_my_friends.composer_hint_cta"}}
        </LinkTo>
        <button
          type="button"
          class="btn btn-flat btn-small local-friends-composer-hint__dismiss"
          aria-label={{i18n "where_is_my_friends.callout_dismiss"}}
          {{on "click" this.dismiss}}
        >{{i18n "where_is_my_friends.callout_dismiss"}}</button>
      </div>
    {{/if}}
  </template>
}
