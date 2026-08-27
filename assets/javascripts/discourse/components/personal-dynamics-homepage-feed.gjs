import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import PersonalDynamicsCard from "discourse/plugins/where-is-my-friends/discourse/components/personal-dynamics-card";
import { createClientTelemetry } from "discourse/plugins/where-is-my-friends/discourse/lib/client-telemetry";

const HOMEPAGE_DYNAMIC_LIMIT = 2;

export default class PersonalDynamicsHomepageFeed extends Component {
  @service currentUser;

  @tracked dynamics = [];
  @tracked loading = true;
  @tracked error = null;
  viewRecorded = false;
  telemetry = createClientTelemetry({
    surface: "homepage",
    recommendationGroup: "dynamics",
  });

  constructor(owner, args) {
    super(owner, args);
    void this.load();
  }

  get ownDynamicsUrl() {
    return `/u/${this.currentUser.username}/activity/dynamics`;
  }

  @action
  trackOpen() {
    void this.telemetry.record("dynamic_opened");
  }

  @action
  async retry() {
    await this.load();
  }

  async load() {
    this.loading = true;
    this.error = null;
    try {
      const result = await ajax("/where-is-my-friends/dynamics/feed.json", {
        data: { limit: HOMEPAGE_DYNAMIC_LIMIT },
      });
      this.dynamics = (result.dynamics ?? []).slice(0, HOMEPAGE_DYNAMIC_LIMIT);
      if (!this.viewRecorded) {
        this.viewRecorded = true;
        void this.telemetry.record("recent_dynamics_viewed");
      }
    } catch {
      this.error = i18n("where_is_my_friends.dynamics.feed_load_error");
    } finally {
      this.loading = false;
    }
  }

  <template>
    <section
      class="personal-dynamics-homepage"
      data-test-personal-dynamics-homepage
    >
      <header class="personal-dynamics-homepage__header">
        <div>
          <p class="personal-dynamics-homepage__eyebrow">{{i18n
              "where_is_my_friends.dynamics.feed_eyebrow"
            }}</p>
          <h2>{{i18n "where_is_my_friends.dynamics.feed_title"}}</h2>
          <p>{{i18n "where_is_my_friends.dynamics.feed_description"}}</p>
        </div>
        <div class="personal-dynamics-homepage__actions">
          <a
            class="btn btn-flat"
            href="/where-is-my-friends/dynamics"
            data-test-personal-dynamics-browse
          >{{i18n "where_is_my_friends.dynamics.view_all"}}</a>
          <a
            class="btn btn-primary"
            href={{this.ownDynamicsUrl}}
            data-test-personal-dynamics-publish-homepage
          >{{i18n "where_is_my_friends.dynamics.publish"}}</a>
        </div>
      </header>

      {{#if this.loading}}
        <p role="status" data-test-personal-dynamics-homepage-loading>{{i18n
            "where_is_my_friends.dynamics.loading"
          }}</p>
      {{else if this.error}}
        <div class="personal-dynamics-homepage__state" role="alert">
          <span>{{this.error}}</span>
          <DButton
            @action={{this.retry}}
            @label="where_is_my_friends.dynamics.retry"
            class="btn-flat"
            data-test-personal-dynamics-homepage-retry
          />
        </div>
      {{else if this.dynamics.length}}
        <div class="personal-dynamics-homepage__list">
          {{#each this.dynamics as |dynamic|}}
            <PersonalDynamicsCard
              @dynamic={{dynamic}}
              @onOpen={{this.trackOpen}}
              @showAuthor={{true}}
              @compact={{true}}
            />
          {{/each}}
        </div>
      {{else}}
        <div class="personal-dynamics-homepage__state">
          <span>{{i18n "where_is_my_friends.dynamics.feed_empty"}}</span>
          <a class="btn btn-primary" href={{this.ownDynamicsUrl}}>{{i18n
              "where_is_my_friends.dynamics.publish"
            }}</a>
        </div>
      {{/if}}
    </section>
  </template>
}
