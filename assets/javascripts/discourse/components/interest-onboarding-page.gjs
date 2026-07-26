import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { eq, not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class InterestOnboardingPage extends Component {
  @service currentUser;

  @tracked state;
  @tracked selectedInterestIds;
  @tracked purpose;
  @tracked recommendable;
  @tracked showInterestsPublicly;
  @tracked recommendedTopics;
  @tracked recommendedUsers;
  @tracked editing;
  @tracked loading = false;
  @tracked error = null;

  constructor() {
    super(...arguments);
    this.state = this.args.model.state;
    const visibleInterestIds = new Set(
      (this.args.model.catalogue ?? []).map((interest) => interest.id)
    );
    this.selectedInterestIds = new Set(
      (this.args.model.profile?.interests ?? [])
        .map((interest) => interest.id)
        .filter((interestId) => visibleInterestIds.has(interestId))
    );
    this.purpose = this.args.model.profile?.purpose ?? null;
    this.recommendable = this.args.model.profile?.recommendable ?? true;
    this.showInterestsPublicly =
      this.args.model.profile?.show_interests_publicly ?? false;
    this.recommendedTopics = this.args.model.recommended_topics ?? [];
    this.recommendedUsers = this.args.model.recommended_users ?? [];
    this.editing = this.state !== "complete";
  }

  get catalogue() {
    return this.args.model.catalogue ?? [];
  }

  get purposeOptions() {
    return (this.args.model.purposes ?? []).map((purpose) => ({
      id: purpose,
      selected: this.purpose === purpose,
      label: i18n(`where_is_my_friends.interests.purposes.${purpose}`),
    }));
  }

  get interestOptions() {
    return this.catalogue.map((interest) => ({
      ...interest,
      selected: this.selectedInterestIds.has(interest.id),
    }));
  }

  get minimumInterests() {
    return Math.min(3, this.catalogue.length);
  }

  get canSave() {
    return (
      !this.loading &&
      this.purpose &&
      this.selectedInterestIds.size >= this.minimumInterests &&
      this.selectedInterestIds.size <= 5
    );
  }

  get hasRecommendations() {
    return (
      this.recommendedTopics.length > 0 || this.recommendedUsers.length > 0
    );
  }

  @action
  initialize() {
    void this.recordEvent("interest_onboarding_viewed");
  }

  @action
  toggleInterest(interestId) {
    const next = new Set(this.selectedInterestIds);
    if (next.has(interestId)) {
      next.delete(interestId);
    } else if (next.size < 5) {
      next.add(interestId);
    }
    this.selectedInterestIds = next;
    this.error = null;
  }

  @action
  selectPurpose(purpose) {
    this.purpose = purpose;
    this.error = null;
  }

  @action
  updateRecommendable(event) {
    this.recommendable = event.target.checked;
  }

  @action
  updatePublicInterests(event) {
    this.showInterestsPublicly = event.target.checked;
  }

  @action
  async save() {
    if (!this.canSave) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await ajax(
        "/where-is-my-friends/recommendations/profile.json",
        {
          type: "PUT",
          data: {
            interest_ids: [...this.selectedInterestIds],
            purpose: this.purpose,
            recommendable: this.recommendable,
            show_interests_publicly: this.showInterestsPublicly,
          },
        }
      );
      this.applyResponse(response);
      this.editing = false;
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async skip() {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await ajax(
        "/where-is-my-friends/recommendations/skip.json",
        { type: "POST" }
      );
      this.state = response.state;
      this.editing = false;
      this.updateCurrentUserState(response.state);
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  edit() {
    this.editing = true;
  }

  @action
  async dismiss(targetType, targetId) {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await ajax(
        "/where-is-my-friends/recommendations/dismiss.json",
        {
          type: "POST",
          data: { target_type: targetType, target_id: targetId },
        }
      );
      this.applyResponse(response);
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async disablePersonalization() {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await ajax(
        "/where-is-my-friends/recommendations/profile.json",
        { type: "DELETE" }
      );
      this.state = response.state;
      this.selectedInterestIds = new Set();
      this.purpose = null;
      this.recommendable = true;
      this.showInterestsPublicly = false;
      this.recommendedTopics = [];
      this.recommendedUsers = [];
      this.editing = false;
      this.updateCurrentUserState(response.state);
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  trackTopicOpen() {
    void this.recordEvent("recommended_topic_opened");
  }

  @action
  trackUserOpen() {
    void this.recordEvent("recommended_user_opened");
  }

  applyResponse(response) {
    this.state = response.state;
    this.recommendedTopics = response.recommended_topics ?? [];
    this.recommendedUsers = response.recommended_users ?? [];
    this.updateCurrentUserState(response.state);
  }

  updateCurrentUserState(state) {
    if (this.currentUser?.set) {
      this.currentUser.set(
        "where_is_my_friends_interest_onboarding_state",
        state
      );
    } else if (this.currentUser) {
      this.currentUser.where_is_my_friends_interest_onboarding_state = state;
    }
  }

  async recordEvent(eventName) {
    try {
      await ajax("/where-is-my-friends/events.json", {
        type: "POST",
        data: { event_name: eventName },
      });
    } catch {
      // Analytics must never block community discovery.
    }
  }

  errorMessage(error) {
    const response = error?.jqXHR?.responseJSON ?? error?.responseJSON;
    return (
      response?.errors?.[0] ??
      i18n("where_is_my_friends.interests.generic_error")
    );
  }

  <template>
    <main
      class="interest-onboarding"
      data-state={{this.state}}
      {{didInsert this.initialize}}
    >
      <header class="interest-onboarding__header">
        <p class="interest-onboarding__eyebrow">{{i18n
            "where_is_my_friends.interests.eyebrow"
          }}</p>
        <h1>{{i18n "where_is_my_friends.interests.title"}}</h1>
        <p>{{i18n "where_is_my_friends.interests.description"}}</p>
      </header>

      {{#if this.error}}
        <div class="alert alert-error" data-test-interest-error>
          {{this.error}}
        </div>
      {{/if}}

      {{#if this.loading}}
        <div
          class="alert alert-info"
          role="status"
          data-test-interest-loading
        >
          {{i18n "where_is_my_friends.interests.loading"}}
        </div>
      {{/if}}

      {{#if this.editing}}
        <section
          class="interest-onboarding__form"
          data-test-interest-onboarding-form
        >
          {{#if this.catalogue.length}}
            <fieldset>
              <legend>{{i18n
                  "where_is_my_friends.interests.choose_interests"
                }}</legend>
              <p>{{i18n
                  "where_is_my_friends.interests.choose_interests_help"
                }}</p>
              <div
                class="interest-onboarding__chips"
                data-test-interest-options
              >
                {{#each this.interestOptions as |interest|}}
                  <DButton
                    @action={{fn this.toggleInterest interest.id}}
                    @translatedLabel={{interest.name}}
                    @icon={{if interest.selected "check" "plus"}}
                    @disabled={{this.loading}}
                    class={{if interest.selected "btn-primary" "btn-default"}}
                    aria-pressed={{if interest.selected "true" "false"}}
                    data-test-interest={{interest.name}}
                  />
                {{/each}}
              </div>
              <p
                class="interest-onboarding__selection-count"
                data-test-interest-count
              >{{i18n
                  "where_is_my_friends.interests.selection_count"
                  count=this.selectedInterestIds.size
                }}</p>
            </fieldset>

            <fieldset>
              <legend>{{i18n
                  "where_is_my_friends.interests.choose_purpose"
                }}</legend>
              <div
                class="interest-onboarding__chips"
                data-test-purpose-options
              >
                {{#each this.purposeOptions as |option|}}
                  <DButton
                    @action={{fn this.selectPurpose option.id}}
                    @translatedLabel={{option.label}}
                    @disabled={{this.loading}}
                    class={{if option.selected "btn-primary" "btn-default"}}
                    aria-pressed={{if option.selected "true" "false"}}
                    data-test-purpose={{option.id}}
                  />
                {{/each}}
              </div>
            </fieldset>

            <fieldset class="interest-onboarding__privacy">
              <legend>{{i18n
                  "where_is_my_friends.interests.privacy_title"
                }}</legend>
              <label>
                <input
                  type="checkbox"
                  checked={{this.recommendable}}
                  data-test-recommendable
                  {{on "change" this.updateRecommendable}}
                />
                <span>{{i18n
                    "where_is_my_friends.interests.recommendable"
                  }}</span>
              </label>
              <label>
                <input
                  type="checkbox"
                  checked={{this.showInterestsPublicly}}
                  data-test-public-interests
                  {{on "change" this.updatePublicInterests}}
                />
                <span>{{i18n
                    "where_is_my_friends.interests.public_interests"
                  }}</span>
              </label>
              <p>{{i18n
                  "where_is_my_friends.interests.private_by_default"
                }}</p>
            </fieldset>

            <div class="interest-onboarding__form-actions">
              <DButton
                @action={{this.save}}
                @label="where_is_my_friends.interests.save"
                @icon="sparkles"
                @disabled={{not this.canSave}}
                class="btn-primary"
                data-test-save-interests
              />
              {{#if (eq this.state "pending")}}
                <DButton
                  @action={{this.skip}}
                  @label="where_is_my_friends.interests.skip"
                  @disabled={{this.loading}}
                  class="btn-flat"
                  data-test-skip-interests
                />
              {{/if}}
            </div>
          {{else}}
            <div class="alert alert-info" data-test-interest-catalogue-empty>
              {{i18n "where_is_my_friends.interests.catalogue_empty"}}
            </div>
            <DButton
              @action={{this.skip}}
              @label="where_is_my_friends.interests.skip"
              @disabled={{this.loading}}
              class="btn-flat"
              data-test-skip-interests
            />
          {{/if}}
        </section>
      {{else if (eq this.state "dismissed")}}
        <section
          class="interest-onboarding__dismissed"
          data-test-interest-dismissed
        >
          <h2>{{i18n "where_is_my_friends.interests.dismissed_title"}}</h2>
          <p>{{i18n "where_is_my_friends.interests.dismissed_description"}}</p>
          <DButton
            @action={{this.edit}}
            @label="where_is_my_friends.interests.enable"
            @icon="sparkles"
            class="btn-primary"
            data-test-enable-interests
          />
        </section>
      {{else}}
        <section class="interest-onboarding__results">
          <div class="interest-onboarding__results-header">
            <div>
              <h2>{{i18n
                  "where_is_my_friends.interests.results_title"
                }}</h2>
              <p>{{i18n
                  "where_is_my_friends.interests.results_description"
                }}</p>
            </div>
            <DButton
              @action={{this.edit}}
              @label="where_is_my_friends.interests.edit"
              @icon="pencil"
              class="btn-flat"
              data-test-edit-interests
            />
          </div>

          {{#if this.hasRecommendations}}
            {{#if this.recommendedTopics.length}}
              <h3>{{i18n
                  "where_is_my_friends.interests.recommended_topics"
                }}</h3>
              <div class="interest-onboarding__topic-grid">
                {{#each this.recommendedTopics as |topic|}}
                  <article data-test-recommended-topic={{topic.id}}>
                    <a href={{topic.url}} {{on "click" this.trackTopicOpen}}>
                      <h4>{{topic.fancy_title}}</h4>
                    </a>
                    <p>{{i18n
                        "where_is_my_friends.interests.topic_reason"
                      }}
                      {{#each topic.matching_interests as |interest|}}
                        <span class="interest-onboarding__reason">
                          {{interest.name}}
                        </span>
                      {{/each}}
                    </p>
                    <DButton
                      @action={{fn this.dismiss "topic" topic.id}}
                      @label="where_is_my_friends.interests.not_interested"
                      @disabled={{this.loading}}
                      class="btn-flat"
                      data-test-dismiss-topic={{topic.id}}
                    />
                  </article>
                {{/each}}
              </div>
            {{/if}}

            {{#if this.recommendedUsers.length}}
              <h3>{{i18n
                  "where_is_my_friends.interests.recommended_people"
                }}</h3>
              <div class="interest-onboarding__people-grid">
                {{#each this.recommendedUsers as |user|}}
                  <article data-test-recommended-user={{user.username}}>
                    <div>
                      <a
                        href={{user.profile_url}}
                        {{on "click" this.trackUserOpen}}
                      >
                        <h4>{{if user.name user.name user.username}}</h4>
                        <span>@{{user.username}}</span>
                      </a>
                      {{#if user.bio_excerpt}}
                        <p>{{user.bio_excerpt}}</p>
                      {{/if}}
                    </div>
                    <p>
                      {{i18n "where_is_my_friends.interests.person_reason"}}
                      {{#each user.reason_interests as |interest|}}
                        <span class="interest-onboarding__reason">
                          {{interest.name}}
                        </span>
                      {{/each}}
                    </p>
                    {{#if user.representative_topics.length}}
                      <ul>
                        {{#each user.representative_topics as |topic|}}
                          <li>
                            <a
                              href={{topic.url}}
                              {{on "click" this.trackTopicOpen}}
                            >{{topic.title}}</a>
                          </li>
                        {{/each}}
                      </ul>
                    {{/if}}
                    <DButton
                      @action={{fn this.dismiss "user" user.id}}
                      @label="where_is_my_friends.interests.not_interested"
                      @disabled={{this.loading}}
                      class="btn-flat"
                      data-test-dismiss-user={{user.id}}
                    />
                  </article>
                {{/each}}
              </div>
            {{/if}}
          {{else}}
            <div
              class="interest-onboarding__empty"
              data-test-recommendations-empty
            >
              <h3>{{i18n "where_is_my_friends.interests.empty_title"}}</h3>
              <p>{{i18n
                  "where_is_my_friends.interests.empty_description"
                }}</p>
            </div>
          {{/if}}

          <details class="interest-onboarding__settings">
            <summary>{{i18n
                "where_is_my_friends.interests.settings"
              }}</summary>
            <p>{{i18n
                "where_is_my_friends.interests.disable_description"
              }}</p>
            <DButton
              @action={{this.disablePersonalization}}
              @label="where_is_my_friends.interests.disable"
              @icon="trash-can"
              @disabled={{this.loading}}
              class="btn-danger"
              data-test-disable-personalization
            />
          </details>
        </section>
      {{/if}}
    </main>
  </template>
}
