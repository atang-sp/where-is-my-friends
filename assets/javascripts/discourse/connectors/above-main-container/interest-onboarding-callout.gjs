import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action, get } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import CommunityDiscoveryPanel from "discourse/plugins/where-is-my-friends/discourse/components/community-discovery-panel";
import {
  HOMEPAGE_DISCOVERY_ENTRIES,
  homepageDiscoveryEntry,
} from "discourse/plugins/where-is-my-friends/discourse/lib/homepage-discovery-entry";

export default class InterestOnboardingCallout extends Component {
  static shouldRender(_args, { currentUser, siteSettings }) {
    return Boolean(
      currentUser &&
      siteSettings.where_is_my_friends_enabled &&
      siteSettings.where_is_my_friends_interest_onboarding_enabled
    );
  }

  @service currentUser;
  @service router;
  @service siteSettings;

  @tracked dismissed = false;

  get onboardingState() {
    return get(
      this.currentUser,
      "where_is_my_friends_interest_onboarding_state"
    );
  }

  get shouldShowPrompt() {
    return (
      this.homepageEntry === HOMEPAGE_DISCOVERY_ENTRIES.INTEREST_ONBOARDING &&
      !this.dismissed &&
      this.isTopicListRoute
    );
  }

  get shouldShowDiscovery() {
    return (
      this.homepageEntry === HOMEPAGE_DISCOVERY_ENTRIES.COMMUNITY &&
      this.isHomeRoute
    );
  }

  get homepageEntry() {
    return homepageDiscoveryEntry({
      onboardingState: this.onboardingState,
      enabled:
        this.siteSettings.where_is_my_friends_interest_onboarding_enabled,
    });
  }

  get isHomeRoute() {
    const routeName = this.router.currentRouteName ?? "";
    return (
      !this.isCategoryRoute &&
      (routeName === "discovery" || routeName.startsWith("discovery."))
    );
  }

  get isCategoryRoute() {
    const routeName = this.router.currentRouteName ?? "";
    return Boolean(
      routeName === "discovery.categories" ||
      routeName.startsWith("category.") ||
      this.router.currentRoute?.attributes?.category
    );
  }

  get isTopicListRoute() {
    return this.isHomeRoute || this.isCategoryRoute;
  }

  @action
  recordPrompt() {
    void this.recordEvent("interest_prompt_viewed");
  }

  @action
  async skip() {
    try {
      const response = await ajax(
        "/where-is-my-friends/recommendations/skip.json",
        { type: "POST" }
      );
      this.currentUser.set(
        "where_is_my_friends_interest_onboarding_state",
        response.state
      );
      this.dismissed = true;
    } catch {
      // A non-critical prompt must never block the topic list.
    }
  }

  async recordEvent(eventName) {
    try {
      await ajax("/where-is-my-friends/events.json", {
        type: "POST",
        data: { event_name: eventName },
      });
    } catch {
      // Analytics must never block the topic list.
    }
  }

  <template>
    {{#if this.shouldShowPrompt}}
      <section
        class="interest-onboarding-callout"
        data-test-interest-onboarding-callout
        {{didInsert this.recordPrompt}}
      >
        <div>
          <strong>{{i18n
              "where_is_my_friends.interests.callout_title"
            }}</strong>
          <p>{{i18n "where_is_my_friends.interests.callout_description"}}</p>
        </div>
        <LinkTo
          @route="where-is-my-friends-interests"
          class="btn btn-primary"
          data-test-open-interest-onboarding
        >
          {{i18n "where_is_my_friends.interests.callout_cta"}}
        </LinkTo>
        <DButton
          @action={{this.skip}}
          @label="where_is_my_friends.interests.skip"
          class="btn-flat"
          data-test-skip-interest-callout
        />
      </section>
    {{else if this.shouldShowDiscovery}}
      <CommunityDiscoveryPanel />
    {{/if}}
  </template>
}
