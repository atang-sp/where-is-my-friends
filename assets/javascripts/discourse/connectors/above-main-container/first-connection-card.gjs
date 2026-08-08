import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { registerDestructor } from "@ember/destroyable";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { defaultHomepage } from "discourse/lib/utilities";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { createClientTelemetry } from "discourse/plugins/where-is-my-friends/discourse/lib/client-telemetry";
import {
  firstConnectionCooldownActive,
  startFirstConnectionCooldown,
} from "discourse/plugins/where-is-my-friends/discourse/lib/first-connection-cooldown";

const ALGORITHM_VERSION = "first_connection_v1";
const ACTION_EVENTS = {
  onboarding: "first_connection_onboarding_opened",
  incoming_invitation: "first_connection_invitation_opened",
  continue_conversation: "first_connection_conversation_opened",
  topic: "first_connection_topic_opened",
  person: "first_connection_person_opened",
  dynamic: "first_connection_dynamic_opened",
  local_discovery: "first_connection_local_opened",
  recommendations: "first_connection_recommendations_opened",
};
const ACTION_STATES = new Set(Object.keys(ACTION_EVENTS));

function safeLocalUrl(url) {
  return (
    typeof url === "string" && url.startsWith("/") && !url.startsWith("//")
  );
}

function validActionPayload(payload) {
  return Boolean(
    ACTION_STATES.has(payload?.state) &&
    payload.title_key &&
    payload.description_key &&
    payload.primary_action?.label_key &&
    safeLocalUrl(payload.primary_action.url) &&
    (!payload.secondary_action ||
      (payload.secondary_action.label_key &&
        safeLocalUrl(payload.secondary_action.url)))
  );
}

export default class FirstConnectionCard extends Component {
  static shouldRender(_args, { currentUser, siteSettings }) {
    return Boolean(
      currentUser &&
      siteSettings.where_is_my_friends_enabled &&
      siteSettings.where_is_my_friends_first_connection_enabled
    );
  }

  @service router;
  @service firstConnectionHomepage;

  @tracked status = firstConnectionCooldownActive() ? "dismissed" : "loading";
  @tracked nextAction = null;
  telemetry = createClientTelemetry({ surface: "homepage" });
  loaded = false;
  viewed = false;

  constructor() {
    super(...arguments);
    registerDestructor(this, () => {
      this.firstConnectionHomepage.release(this);
    });

    if (this.status === "loading" && this.isHomeRoute) {
      this.claimHomepage();
    }
  }

  get isHomeRoute() {
    const routeName = this.router.currentRouteName ?? "";
    return routeName === `discovery.${defaultHomepage()}`;
  }

  get isLoading() {
    return this.status === "loading";
  }

  get isReady() {
    return this.status === "ready";
  }

  get title() {
    return i18n(this.nextAction.title_key);
  }

  get description() {
    return i18n(this.nextAction.description_key);
  }

  get primaryLabel() {
    return i18n(this.nextAction.primary_action.label_key);
  }

  get secondaryLabel() {
    return i18n(this.nextAction.secondary_action.label_key);
  }

  get telemetryContext() {
    return {
      algorithmVersion: this.nextAction?.algorithm_version ?? ALGORITHM_VERSION,
      recommendationGroup: this.nextAction?.recommendation_group,
    };
  }

  @action
  async load() {
    if (this.loaded) {
      return;
    }

    if (firstConnectionCooldownActive()) {
      this.status = "dismissed";
      this.firstConnectionHomepage.release(this);
      return;
    }

    this.claimHomepage();
    this.loaded = true;

    try {
      const payload = await ajax("/where-is-my-friends/next-action.json");
      if (payload?.state === "empty") {
        this.status = "empty";
        this.firstConnectionHomepage.release(this);
      } else if (validActionPayload(payload)) {
        this.nextAction = payload;
        this.status = "ready";
      } else {
        this.status = "error";
        this.firstConnectionHomepage.release(this);
      }
    } catch {
      this.status = "error";
      this.firstConnectionHomepage.release(this);
    }
  }

  claimHomepage() {
    this.firstConnectionHomepage.claim(this, this.router.currentRouteName);
  }

  @action
  recordView() {
    this.claimHomepage();
    if (this.viewed) {
      return;
    }
    this.viewed = true;
    void this.telemetry.record(
      "first_connection_card_viewed",
      this.telemetryContext
    );
  }

  @action
  trackPrimaryOpen() {
    const eventName = ACTION_EVENTS[this.nextAction.state];
    void this.telemetry.record(eventName, this.telemetryContext);
  }

  @action
  trackSecondaryOpen() {
    void this.telemetry.record(
      "first_connection_recommendations_opened",
      this.telemetryContext
    );
  }

  @action
  dismiss() {
    startFirstConnectionCooldown();
    this.status = "dismissed";
    this.firstConnectionHomepage.release(this);
    void this.telemetry.record(
      "first_connection_card_dismissed",
      this.telemetryContext
    );
  }

  <template>
    {{#if this.isHomeRoute}}
      {{#if this.isLoading}}
        <section
          class="first-connection-card first-connection-card--loading"
          aria-label={{i18n "where_is_my_friends.first_connection.loading"}}
          aria-busy="true"
          data-test-first-connection-loading
          {{didInsert this.load}}
        >
          <div class="first-connection-card__skeleton-line"></div>
          <div class="first-connection-card__skeleton-line"></div>
        </section>
      {{else if this.isReady}}
        <section
          class="first-connection-card"
          data-state={{this.nextAction.state}}
          data-test-first-connection-card
          {{didInsert this.recordView}}
        >
          <div class="first-connection-card__content">
            <p class="first-connection-card__eyebrow">
              {{i18n "where_is_my_friends.first_connection.eyebrow"}}
            </p>
            <h2>{{this.title}}</h2>
            <p class="first-connection-card__description">
              {{this.description}}
            </p>
          </div>
          <div
            class="first-connection-card__actions"
            data-test-first-connection-actions
          >
            <a
              href={{this.nextAction.primary_action.url}}
              class="btn btn-primary"
              data-test-first-connection-primary
              {{on "click" this.trackPrimaryOpen}}
            >
              {{this.primaryLabel}}
            </a>
            {{#if this.nextAction.secondary_action}}
              <a
                href={{this.nextAction.secondary_action.url}}
                class="first-connection-card__secondary"
                data-test-first-connection-secondary
                {{on "click" this.trackSecondaryOpen}}
              >
                {{this.secondaryLabel}}
              </a>
            {{/if}}
          </div>
          <DButton
            @action={{this.dismiss}}
            @icon="xmark"
            @ariaLabel="where_is_my_friends.first_connection.dismiss"
            @title="where_is_my_friends.first_connection.dismiss"
            class="btn-flat no-text first-connection-card__dismiss"
            data-test-dismiss-first-connection
          />
        </section>
      {{/if}}
    {{/if}}
  </template>
}
