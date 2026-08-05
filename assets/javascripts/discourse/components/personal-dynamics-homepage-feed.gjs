import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import PersonalDynamicsCard from "discourse/plugins/where-is-my-friends/discourse/components/personal-dynamics-card";

export default class PersonalDynamicsHomepageFeed extends Component {
  @service currentUser;

  @tracked dynamics = [];
  @tracked hasMore = false;
  @tracked beforeId = null;
  @tracked loading = true;
  @tracked loadingMore = false;
  @tracked error = null;
  viewRecorded = false;

  constructor(owner, args) {
    super(owner, args);
    void this.load();
  }

  get ownDynamicsUrl() {
    return `/u/${this.currentUser.username}/activity/dynamics`;
  }

  @action
  async loadMore() {
    if (this.loadingMore || !this.hasMore) {
      return;
    }

    this.loadingMore = true;
    await this.load(this.beforeId, true);
    this.loadingMore = false;
  }

  @action
  trackOpen() {
    void this.recordEvent("dynamic_opened");
  }

  @action
  async retry() {
    await this.load();
  }

  async load(beforeId = null, append = false) {
    if (!append) {
      this.loading = true;
    }
    this.error = null;
    try {
      const data = beforeId ? { before_id: beforeId } : undefined;
      const result = await ajax("/where-is-my-friends/dynamics/feed.json", {
        data,
      });
      this.dynamics = append
        ? [...this.dynamics, ...(result.dynamics ?? [])]
        : (result.dynamics ?? []);
      this.hasMore = Boolean(result.has_more);
      this.beforeId = result.before_id;
      if (!append && !this.viewRecorded) {
        this.viewRecorded = true;
        void this.recordEvent("recent_dynamics_viewed");
      }
    } catch {
      this.error = i18n("where_is_my_friends.dynamics.feed_load_error");
    } finally {
      if (!append) {
        this.loading = false;
      }
    }
  }

  async recordEvent(eventName) {
    try {
      await ajax("/where-is-my-friends/events.json", {
        type: "POST",
        data: {
          event_name: eventName,
          surface: "homepage",
          recommendation_group: "dynamics",
        },
      });
    } catch {
      // Measurement must never block the homepage feed.
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
        {{#if this.hasMore}}
          <DButton
            @action={{this.loadMore}}
            @label="where_is_my_friends.dynamics.load_more_feed"
            @disabled={{this.loadingMore}}
            class="btn-default personal-dynamics-homepage__load-more"
            data-test-personal-dynamics-homepage-load-more
          />
        {{/if}}
      {{else}}
        <div class="personal-dynamics-homepage__state">
          <span>{{i18n "where_is_my_friends.dynamics.feed_empty"}}</span>
          <a
            class="btn btn-primary"
            href={{this.ownDynamicsUrl}}
          >{{i18n "where_is_my_friends.dynamics.publish"}}</a>
        </div>
      {{/if}}
    </section>
  </template>
}
