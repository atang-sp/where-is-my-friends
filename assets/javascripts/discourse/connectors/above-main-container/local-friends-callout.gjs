import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

const DISMISSED_KEY = "local-friends-callout-dismissed";

export default class LocalFriendsCallout extends Component {
  @service currentUser;
  @service router;

  @tracked data = null;
  @tracked dismissed = this.wasDismissed();

  get shouldLoad() {
    return Boolean(
      this.currentUser && !this.dismissed && this.isTopicListRoute
    );
  }

  get isTopicListRoute() {
    const routeName = this.router.currentRouteName ?? "";
    return (
      routeName === "discovery" ||
      routeName.startsWith("discovery.") ||
      routeName.startsWith("category.")
    );
  }

  get hasLocation() {
    return Boolean(this.data?.location);
  }

  get proof() {
    const participants = this.data?.active_participants;
    if (!participants || participants.suppressed) {
      return i18n("where_is_my_friends.callout_proof_generic");
    }

    return i18n("where_is_my_friends.callout_proof_count", {
      count: participants.count,
    });
  }

  wasDismissed() {
    try {
      return sessionStorage.getItem(DISMISSED_KEY) === "true";
    } catch {
      return false;
    }
  }

  @action
  async load() {
    if (this.data) {
      return;
    }

    try {
      this.data = await ajax("/where-is-my-friends.json");
    } catch {
      // The optional entry must never block topic-list rendering.
    }
  }

  @action
  dismiss() {
    this.dismissed = true;
    try {
      sessionStorage.setItem(DISMISSED_KEY, "true");
    } catch {
      // The tracked state still dismisses the callout for the current page.
    }
  }

  <template>
    {{#if this.shouldLoad}}
      <span hidden {{didInsert this.load}}></span>
      {{#if this.data}}
        <section
          class="local-friends-callout"
          data-test-local-friends-callout
        >
          <div class="local-friends-callout__content">
            <strong>{{i18n "where_is_my_friends.callout_title"}}</strong>
            <p>{{i18n
                (if
                  this.hasLocation
                  "where_is_my_friends.callout_returning_description"
                  "where_is_my_friends.callout_setup_description"
                )
              }}</p>
            <span data-test-local-friends-callout-proof>{{this.proof}}</span>
          </div>
          <LinkTo
            @route="where-is-my-friends"
            class="btn btn-primary"
            data-test-local-friends-callout-cta
          >
            {{i18n
              (if
                this.hasLocation
                "where_is_my_friends.callout_view_members"
                "where_is_my_friends.callout_set_city"
              )
            }}
          </LinkTo>
          <DButton
            @action={{this.dismiss}}
            @icon="xmark"
            @ariaLabel="where_is_my_friends.callout_dismiss"
            @title="where_is_my_friends.callout_dismiss"
            class="btn-flat no-text local-friends-callout__dismiss"
            data-test-dismiss-local-friends
          />
        </section>
      {{/if}}
    {{/if}}
  </template>
}
