import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import { cook } from "discourse/lib/text";
import { not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DDecoratedHtml from "discourse/ui-kit/d-decorated-html";
import DRelativeDate from "discourse/ui-kit/d-relative-date";
import { i18n } from "discourse-i18n";

const graphemeSegmenter =
  typeof Intl.Segmenter === "function"
    ? new Intl.Segmenter(undefined, { granularity: "grapheme" })
    : null;

function graphemeLength(value) {
  const text = value;
  return graphemeSegmenter
    ? Array.from(graphemeSegmenter.segment(text)).length
    : Array.from(text).length;
}

function cookedVisibleText(cooked) {
  const fragment = document.createElement("div");
  fragment.innerHTML = cooked;
  fragment.querySelectorAll("img.emoji").forEach((emoji) => {
    emoji.replaceWith(emoji.title || emoji.alt || "");
  });
  return fragment.textContent.replace(/\s+/g, " ").trim();
}

class DynamicCard extends Component {
  get cooked() {
    return trustHTML(this.args.dynamic.cooked ?? "");
  }

  <template>
    <article
      class="personal-dynamics__card"
      data-test-personal-dynamic={{@dynamic.id}}
    >
      <DDecoratedHtml
        @html={{this.cooked}}
        @className="personal-dynamics__cooked"
      />
      <footer class="personal-dynamics__meta">
        <span><DRelativeDate @date={{@dynamic.created_at}} /></span>
        <span>{{i18n
            "where_is_my_friends.dynamics.reply_count"
            count=@dynamic.reply_count
          }}</span>
        <a
          href={{@dynamic.url}}
          data-test-personal-dynamic-open
          {{on "click" @onOpen}}
        >{{i18n "where_is_my_friends.dynamics.open_and_reply"}}</a>
      </footer>
    </article>
  </template>
}

export default class PersonalDynamicsPage extends Component {
  @service currentUser;

  @tracked dynamics = [];
  @tracked hasMore = false;
  @tracked beforeId = null;
  @tracked raw = "";
  @tracked visibleLength = 0;
  @tracked loading = true;
  @tracked loadingMore = false;
  @tracked publishing = false;
  @tracked error = null;
  @tracked publishNotice = null;
  lengthRequest = 0;

  constructor(owner, args) {
    super(owner, args);
    void this.load();
    void this.recordEvent("dynamics_profile_viewed");
  }

  get isSelf() {
    return this.currentUser?.username === this.args.user?.username;
  }

  get canPublish() {
    return (
      !this.publishing &&
      this.visibleLength >= 8 &&
      this.visibleLength <= 500
    );
  }

  @action
  async updateRaw(event) {
    this.raw = event.target.value;
    const raw = this.raw;
    const request = ++this.lengthRequest;
    try {
      const cooked = await cook(raw);
      if (this.lengthRequest === request) {
        this.visibleLength = graphemeLength(cookedVisibleText(cooked));
      }
    } catch {
      if (this.lengthRequest === request) {
        this.visibleLength = graphemeLength(raw.replace(/\s+/g, " ").trim());
      }
    }
    this.error = null;
    this.publishNotice = null;
  }

  @action
  async publish() {
    if (!this.canPublish) {
      return;
    }

    this.publishing = true;
    this.error = null;
    this.publishNotice = null;
    try {
      const result = await ajax("/where-is-my-friends/dynamics.json", {
        type: "POST",
        data: { raw: this.raw },
      });
      this.raw = "";
      this.visibleLength = 0;
      if (result.queued) {
        this.publishNotice = i18n(
          "where_is_my_friends.dynamics.queued_notice",
        );
      } else if (result.dynamic) {
        this.dynamics = [
          result.dynamic,
          ...this.dynamics.filter(
            (dynamic) => dynamic.id !== result.dynamic.id,
          ),
        ];
        this.publishNotice = i18n(
          "where_is_my_friends.dynamics.published_notice",
        );
      }
    } catch (error) {
      this.error =
        error?.jqXHR?.responseJSON?.errors?.[0] ??
        i18n("where_is_my_friends.dynamics.publish_error");
    } finally {
      this.publishing = false;
    }
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

  async load(beforeId = null, append = false) {
    if (!append) {
      this.loading = true;
    }
    this.error = null;
    try {
      const data = { username: this.args.user.username };
      if (beforeId) {
        data.before_id = beforeId;
      }
      const result = await ajax("/where-is-my-friends/dynamics.json", {
        data,
      });
      this.dynamics = append
        ? [...this.dynamics, ...(result.dynamics ?? [])]
        : (result.dynamics ?? []);
      this.hasMore = Boolean(result.has_more);
      this.beforeId = result.before_id;
    } catch {
      this.error = i18n("where_is_my_friends.dynamics.load_error");
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
          surface: "profile",
          recommendation_group: "dynamics",
        },
      });
    } catch {
      // Measurement must never block personal dynamics.
    }
  }

  <template>
    <section class="personal-dynamics" data-test-personal-dynamics>
      <header class="personal-dynamics__header">
        <h2>{{i18n
            "where_is_my_friends.dynamics.title"
            username=@user.username
          }}</h2>
        <p>{{i18n "where_is_my_friends.dynamics.description"}}</p>
      </header>

      {{#if this.isSelf}}
        <section
          class="personal-dynamics__publisher"
          aria-labelledby="personal-dynamics-publisher-title"
          data-test-personal-dynamics-publisher
        >
          <h3 id="personal-dynamics-publisher-title">{{i18n
              "where_is_my_friends.dynamics.publisher_title"
            }}</h3>
          <label for="personal-dynamics-raw">{{i18n
              "where_is_my_friends.dynamics.publisher_label"
            }}</label>
          <textarea
            id="personal-dynamics-raw"
            rows="5"
            value={{this.raw}}
            placeholder={{i18n
              "where_is_my_friends.dynamics.publisher_placeholder"
            }}
            aria-describedby="personal-dynamics-guidance personal-dynamics-count"
            data-test-personal-dynamics-input
            {{on "input" this.updateRaw}}
          ></textarea>
          <div class="personal-dynamics__publisher-meta">
            <p id="personal-dynamics-guidance">{{i18n
                "where_is_my_friends.dynamics.publisher_guidance"
              }}</p>
            <span
              id="personal-dynamics-count"
              data-test-personal-dynamics-count
            >{{i18n
                "where_is_my_friends.dynamics.character_count"
                count=this.visibleLength
              }}</span>
          </div>
          <DButton
            @action={{this.publish}}
            @label="where_is_my_friends.dynamics.publish"
            @icon="paper-plane"
            @disabled={{not this.canPublish}}
            class="btn-primary"
            data-test-personal-dynamics-publish
          />
        </section>
      {{/if}}

      {{#if this.publishNotice}}
        <p
          class="personal-dynamics__notice"
          role="status"
          data-test-personal-dynamics-notice
        >{{this.publishNotice}}</p>
      {{/if}}
      {{#if this.error}}
        <p
          class="personal-dynamics__error"
          role="alert"
          data-test-personal-dynamics-error
        >{{this.error}}</p>
      {{/if}}

      {{#if this.loading}}
        <p role="status" data-test-personal-dynamics-loading>{{i18n
            "where_is_my_friends.dynamics.loading"
          }}</p>
      {{else if this.dynamics.length}}
        <div class="personal-dynamics__list">
          {{#each this.dynamics as |dynamic|}}
            <DynamicCard @dynamic={{dynamic}} @onOpen={{this.trackOpen}} />
          {{/each}}
        </div>
        {{#if this.hasMore}}
          <DButton
            @action={{this.loadMore}}
            @label="where_is_my_friends.dynamics.load_older"
            @disabled={{this.loadingMore}}
            class="btn-default personal-dynamics__load-more"
            data-test-personal-dynamics-load-more
          />
        {{/if}}
      {{else}}
        <p class="personal-dynamics__empty" data-test-personal-dynamics-empty>
          {{i18n
            (if
              this.isSelf
              "where_is_my_friends.dynamics.empty_self"
              "where_is_my_friends.dynamics.empty_other"
            )
          }}
        </p>
      {{/if}}
    </section>
  </template>
}
