import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

const STORAGE_KEY = "local-friends-callout-state";
const MAX_VIEWS = 2;
const DISMISS_DAYS = 7;

function readCalloutState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return { views: 0, cooldownUntil: null, open: false };
    }
    const parsed = JSON.parse(raw);
    return {
      views: Number(parsed.views) || 0,
      cooldownUntil: parsed.cooldownUntil || null,
      open: Boolean(parsed.open),
    };
  } catch {
    return { views: 0, cooldownUntil: null, open: false };
  }
}

function writeCalloutState(state) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    // Storage may be unavailable; tracked state still controls this page.
  }
}

function shouldHideCallout(state) {
  if (!state.cooldownUntil) {
    return state.views >= MAX_VIEWS && !state.open;
  }

  const cooldownUntil = Date.parse(state.cooldownUntil);
  if (Number.isNaN(cooldownUntil)) {
    return false;
  }

  return Date.now() < cooldownUntil;
}

function shouldCompact(state) {
  return state.views >= MAX_VIEWS;
}

export default class LocalFriendsCallout extends Component {
  @service currentUser;
  @service router;

  @tracked data = null;
  @tracked city = "";
  @tracked saving = false;
  @tracked hasSuggestion = false;
  @tracked error = null;
  @tracked justJoined = false;
  @tracked dismissed = false;
  @tracked compact = false;
  calloutState = readCalloutState();

  constructor() {
    super(...arguments);
    this.compact = shouldCompact(this.calloutState);
  }

  get shouldLoad() {
    return Boolean(this.currentUser && this.isTopicListRoute);
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
    return Boolean(this.data?.location) || this.justJoined;
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

  get joinedCity() {
    return this.data?.location?.city || this.city.trim();
  }

  @action
  async load() {
    if (this.data) {
      return;
    }

    try {
      this.data = await ajax("/where-is-my-friends.json");
      if (!this.data.location && this.data.profile_location) {
        this.city = this.data.profile_location;
        this.hasSuggestion = true;
      }
      this.recordView();
    } catch {
      // The optional entry must never block topic-list rendering.
    }
  }

  recordView() {
    if (this.calloutState.open) {
      return;
    }

    this.calloutState = {
      views: this.calloutState.views + 1,
      cooldownUntil: null,
      open: true,
    };
    writeCalloutState(this.calloutState);
    this.compact = shouldCompact(this.calloutState);
  }

  @action
  updateCity(event) {
    this.city = event.target.value;
    this.error = null;
  }

  @action
  async saveCity(event) {
    event?.preventDefault?.();

    const city = this.city.trim();
    if (!city || this.saving) {
      return;
    }

    this.saving = true;
    this.error = null;

    try {
      const response = await ajax("/where-is-my-friends/locations.json", {
        type: "POST",
        data: { city, discovery_mode: "city" },
      });
      this.data = {
        ...this.data,
        location: response.location,
        state: response.state,
      };
      this.justJoined = true;
    } catch {
      this.error = i18n("where_is_my_friends.callout_save_error");
    } finally {
      this.saving = false;
    }
  }

  @action
  dismiss() {
    const views = Math.max(this.calloutState.views, MAX_VIEWS);
    this.calloutState = {
      views,
      open: false,
      cooldownUntil: this.hasLocation
        ? new Date(
            Date.now() + DISMISS_DAYS * 24 * 60 * 60 * 1000
          ).toISOString()
        : null,
    };
    writeCalloutState(this.calloutState);

    if (this.hasLocation) {
      this.dismissed = true;
    } else {
      this.compact = true;
    }
  }

  <template>
    {{#if this.shouldLoad}}
      <span hidden {{didInsert this.load}}></span>
      {{#if this.data}}
        {{#unless this.dismissed}}
          {{#if this.compact}}
            <section
              class="local-friends-callout-banner local-friends-callout-banner--compact"
              data-test-local-friends-callout
            >
              <div class="local-friends-callout-banner__content">
                <strong>{{i18n "where_is_my_friends.callout_title"}}</strong>
              </div>
              <LinkTo
                @route="where-is-my-friends"
                class="btn btn-primary btn-small"
                data-test-local-friends-callout-cta
              >
                {{i18n "where_is_my_friends.callout_set_city"}}
              </LinkTo>
            </section>
          {{else}}
            <section
              class="local-friends-callout-banner"
              data-test-local-friends-callout
            >
              <div class="local-friends-callout-banner__content">
                {{#if this.justJoined}}
                  <strong>{{i18n
                      "where_is_my_friends.callout_joined_title"
                    }}</strong>
                  <p>{{i18n
                      "where_is_my_friends.callout_joined_description"
                      city=this.joinedCity
                    }}</p>
                {{else}}
                  <strong>{{i18n "where_is_my_friends.callout_title"}}</strong>
                  <p>{{#if this.hasLocation}}
                      {{i18n
                        "where_is_my_friends.callout_returning_description"
                      }}
                    {{else if this.hasSuggestion}}
                      {{i18n
                        "where_is_my_friends.callout_suggestion"
                        city=this.city
                      }}
                    {{else}}
                      {{i18n
                        "where_is_my_friends.callout_setup_description"
                      }}
                    {{/if}}</p>
                  <span
                    data-test-local-friends-callout-proof
                  >{{this.proof}}</span>
                {{/if}}
                {{#if this.error}}
                  <p
                    class="local-friends-callout-banner__error"
                    data-test-callout-error
                  >
                    {{this.error}}
                  </p>
                {{/if}}
              </div>

              {{#if this.hasLocation}}
                <LinkTo
                  @route="where-is-my-friends"
                  class="btn btn-primary"
                  data-test-local-friends-callout-cta
                >
                  {{i18n "where_is_my_friends.callout_view_members"}}
                </LinkTo>
              {{else}}
                <form
                  class="local-friends-callout-banner__setup"
                  data-test-local-friends-callout-setup
                  {{on "submit" this.saveCity}}
                >
                  <input
                    type="text"
                    value={{this.city}}
                    placeholder={{i18n
                      "where_is_my_friends.callout_city_placeholder"
                    }}
                    autocomplete="address-level2"
                    aria-label={{i18n "where_is_my_friends.city"}}
                    data-test-callout-city-input
                    {{on "input" this.updateCity}}
                  />
                  <DButton
                    @action={{this.saveCity}}
                    @label="where_is_my_friends.callout_save_city"
                    @icon="location-dot"
                    @disabled={{this.saving}}
                    class="btn-primary"
                    data-test-callout-save-city
                  />
                </form>
              {{/if}}

              <DButton
                @action={{this.dismiss}}
                @icon="xmark"
                @ariaLabel="where_is_my_friends.callout_dismiss"
                @title="where_is_my_friends.callout_dismiss"
                class="btn-flat no-text local-friends-callout-banner__dismiss"
                data-test-dismiss-local-friends
              />
            </section>
          {{/if}}
        {{/unless}}
      {{/if}}
    {{/if}}
  </template>
}
