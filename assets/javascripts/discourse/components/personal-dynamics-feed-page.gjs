import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import PersonalDynamicsCard from "discourse/plugins/where-is-my-friends/discourse/components/personal-dynamics-card";

export default class PersonalDynamicsFeedPage extends Component {
  @service currentUser;

  @tracked dynamics = [];
  @tracked hasMore = false;
  @tracked beforeId = null;
  @tracked loading = true;
  @tracked loadingMore = false;
  @tracked error = null;

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
    // Opening a dynamic navigates to the native topic interaction surface.
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
    } catch {
      this.error = i18n("where_is_my_friends.dynamics.feed_load_error");
    } finally {
      if (!append) {
        this.loading = false;
      }
    }
  }

  <template>
    <section class="personal-dynamics personal-dynamics--feed" data-test-personal-dynamics-feed>
      <header class="personal-dynamics__header">
        <p class="personal-dynamics__eyebrow">{{i18n
            "where_is_my_friends.dynamics.feed_eyebrow"
          }}</p>
        <h1>{{i18n "where_is_my_friends.dynamics.feed_title"}}</h1>
        <p>{{i18n "where_is_my_friends.dynamics.feed_description"}}</p>
        <div class="personal-dynamics__feed-actions">
          <a
            class="btn btn-primary"
            href={{this.ownDynamicsUrl}}
            data-test-personal-dynamics-feed-publish
          >{{i18n "where_is_my_friends.dynamics.publish"}}</a>
        </div>
      </header>

      {{#if this.loading}}
        <p role="status" data-test-personal-dynamics-feed-loading>{{i18n
            "where_is_my_friends.dynamics.loading"
          }}</p>
      {{else if this.error}}
        <div class="personal-dynamics__state" role="alert">
          <span>{{this.error}}</span>
          <DButton
            @action={{this.retry}}
            @label="where_is_my_friends.dynamics.retry"
            class="btn-flat"
            data-test-personal-dynamics-feed-retry
          />
        </div>
      {{else if this.dynamics.length}}
        <div class="personal-dynamics__list">
          {{#each this.dynamics as |dynamic|}}
            <PersonalDynamicsCard
              @dynamic={{dynamic}}
              @onOpen={{this.trackOpen}}
              @showAuthor={{true}}
            />
          {{/each}}
        </div>
        {{#if this.hasMore}}
          <DButton
            @action={{this.loadMore}}
            @label="where_is_my_friends.dynamics.load_more_feed"
            @disabled={{this.loadingMore}}
            class="btn-default personal-dynamics__load-more"
            data-test-personal-dynamics-feed-load-more
          />
        {{/if}}
      {{else}}
        <p class="personal-dynamics__empty" data-test-personal-dynamics-feed-empty>
          {{i18n "where_is_my_friends.dynamics.feed_empty"}}
        </p>
      {{/if}}
    </section>
  </template>
}
