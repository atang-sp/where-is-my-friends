import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
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
  @service siteSettings;

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
  @tracked invitationSuccess = null;
  @tracked incomingInvitations = [];
  @tracked outgoingInvitations = [];
  @tracked legacyPracticeBookmarks = [];
  @tracked invitationTarget = null;
  @tracked invitationInterestId = null;
  @tracked invitationProposedAt = "";
  @tracked invitationNote = "";
  @tracked interestSearch = "";

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

  get interestGroups() {
    const query = this.interestSearch.trim().toLocaleLowerCase();
    const options = this.interestOptions.filter(
      (interest) =>
        !query || interest.name.toLocaleLowerCase().includes(query)
    );
    const configuredGroups = this.args.model.catalogue_groups ?? [];
    const fallbackGroups = [
      ...new Map(
        options.map((interest) => [
          interest.group_key ?? "community",
          {
            key: interest.group_key ?? "community",
            name: interest.group_name ?? interest.group_key ?? "Community",
            description: "",
          },
        ])
      ).values(),
    ];

    return (configuredGroups.length ? configuredGroups : fallbackGroups)
      .map((group) => ({
        ...group,
        interests: options.filter(
          (interest) => interest.group_key === group.key
        ),
      }))
      .filter((group) => group.interests.length > 0);
  }

  get minimumInterests() {
    return Math.min(
      this.args.model.selection_limits?.minimum ?? 3,
      this.catalogue.length
    );
  }

  get maximumInterests() {
    return this.args.model.selection_limits?.maximum ?? 5;
  }

  get canSave() {
    return (
      !this.loading &&
      this.purpose &&
      this.selectedInterestIds.size >= this.minimumInterests &&
      this.selectedInterestIds.size <= this.maximumInterests
    );
  }

  get hasRecommendations() {
    return (
      this.recommendedTopics.length > 0 || this.recommendedUsers.length > 0
    );
  }

  get invitationInterests() {
    return this.invitationTarget?.invitation_interests ?? [];
  }

  get selectedInvitationInterest() {
    return this.invitationInterests.find(
      (interest) => interest.id === this.invitationInterestId
    );
  }

  get invitationPreview() {
    if (!this.invitationTarget || !this.selectedInvitationInterest) {
      return "";
    }

    return i18n(
      "where_is_my_friends.practice_invitations.preset_message",
      {
        username: this.invitationTarget.username,
        interest: this.selectedInvitationInterest.name,
      }
    );
  }

  @action
  async initialize() {
    void this.recordEvent("interest_onboarding_viewed");
    if (!this.siteSettings.where_is_my_friends_practice_invitations_enabled) {
      return;
    }

    await this.loadInvitations();
    await this.loadLegacyPracticeBookmarks();
    await this.openInvitationFromQuery();
  }

  @action
  toggleInterest(interestId) {
    const next = new Set(this.selectedInterestIds);
    if (next.has(interestId)) {
      next.delete(interestId);
    } else if (next.size < this.maximumInterests) {
      next.add(interestId);
    }
    this.selectedInterestIds = next;
    this.error = null;
  }

  @action
  updateInterestSearch(event) {
    this.interestSearch = event.target.value;
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

  @action
  openInvitation(user) {
    const interests = user.invitation_interests ?? [];
    if (interests.length === 0) {
      return;
    }

    this.invitationTarget = user;
    this.invitationInterestId = interests[0].id;
    this.invitationProposedAt = "";
    this.invitationNote = "";
    this.invitationSuccess = null;
    this.error = null;
  }

  @action
  closeInvitation() {
    this.invitationTarget = null;
    this.invitationInterestId = null;
    this.invitationProposedAt = "";
    this.invitationNote = "";
  }

  @action
  updateInvitationInterest(event) {
    this.invitationInterestId = Number(event.target.value);
  }

  @action
  updateInvitationProposedAt(event) {
    this.invitationProposedAt = event.target.value;
  }

  @action
  updateInvitationNote(event) {
    this.invitationNote = event.target.value;
  }

  @action
  async sendInvitation() {
    if (
      this.loading ||
      !this.invitationTarget ||
      !this.invitationInterestId
    ) {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await ajax(
        "/where-is-my-friends/practice-invitations.json",
        {
          type: "POST",
          data: {
            recipient_id: this.invitationTarget.id,
            tag_id: this.invitationInterestId,
            proposed_at: this.invitationProposedAt
              ? new Date(this.invitationProposedAt).toISOString()
              : null,
            note: this.invitationNote,
          },
        }
      );
      this.outgoingInvitations = [
        response.invitation,
        ...this.outgoingInvitations,
      ];
      this.invitationSuccess = i18n(
        "where_is_my_friends.practice_invitations.sent"
      );
      this.closeInvitation();
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  async respondToInvitation(invitation, responseName) {
    if (this.loading || invitation.status !== "pending") {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await ajax(
        `/where-is-my-friends/practice-invitations/${invitation.id}/${responseName}.json`,
        { type: "PUT" }
      );
      this.incomingInvitations = this.incomingInvitations.map((entry) =>
        entry.id === invitation.id ? response.invitation : entry
      );
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  async loadInvitations() {
    try {
      const response = await ajax(
        "/where-is-my-friends/practice-invitations.json"
      );
      this.incomingInvitations = response.incoming ?? [];
      this.outgoingInvitations = response.outgoing ?? [];
    } catch {
      // Invitations are additive; recommendations remain usable if unavailable.
    }
  }

  async loadLegacyPracticeBookmarks() {
    try {
      const response = await ajax(
        "/where-is-my-friends/legacy-practice-bookmarks.json"
      );
      this.legacyPracticeBookmarks = response.bookmarks ?? [];
    } catch {
      // The legacy table may not exist on a fresh installation.
    }
  }

  @action
  async respondToLegacyBookmark(bookmark, responseName) {
    if (this.loading || bookmark.state !== "needs_reconfirmation") {
      return;
    }

    this.loading = true;
    this.error = null;
    try {
      const response = await ajax(
        `/where-is-my-friends/legacy-practice-bookmarks/${bookmark.id}/${responseName}.json`,
        { type: "PUT" }
      );
      this.legacyPracticeBookmarks = this.legacyPracticeBookmarks.map(
        (entry) => (entry.id === bookmark.id ? response.bookmark : entry)
      );
    } catch (error) {
      this.error = this.errorMessage(error);
    } finally {
      this.loading = false;
    }
  }

  async openInvitationFromQuery() {
    const username = this.args.inviteTo;
    if (!username) {
      return;
    }

    try {
      const response = await ajax(
        "/where-is-my-friends/practice-invitations/availability.json",
        { data: { username } }
      );
      if (response.available) {
        this.openInvitation({
          id: response.recipient_id,
          username: response.username,
          name: response.name,
          invitation_interests: response.interests,
        });
      }
    } catch {
      // The target may no longer be available; keep the main page usable.
    }
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

      {{#if this.invitationSuccess}}
        <div
          class="alert alert-success"
          role="status"
          data-test-practice-invitation-success
        >
          {{this.invitationSuccess}}
        </div>
      {{/if}}

      {{#if this.legacyPracticeBookmarks.length}}
        <section class="interest-onboarding__legacy-bookmarks">
          <div>
            <p class="interest-onboarding__eyebrow">{{i18n
                "where_is_my_friends.legacy_practice_bookmarks.eyebrow"
              }}</p>
            <h2>{{i18n
                "where_is_my_friends.legacy_practice_bookmarks.title"
              }}</h2>
            <p>{{i18n
                "where_is_my_friends.legacy_practice_bookmarks.description"
              }}</p>
          </div>
          <div class="interest-onboarding__legacy-bookmark-list">
            {{#each this.legacyPracticeBookmarks as |bookmark|}}
              <article data-test-legacy-practice-bookmark={{bookmark.id}}>
                <div>
                  <h3>@{{bookmark.target.username}}</h3>
                  {{#if bookmark.mutual_history}}
                    <span>{{i18n
                        "where_is_my_friends.legacy_practice_bookmarks.mutual_history"
                      }}</span>
                  {{/if}}
                </div>
                {{#if (eq bookmark.state "needs_reconfirmation")}}
                  <p>{{i18n
                      "where_is_my_friends.legacy_practice_bookmarks.no_auto_invite"
                    }}</p>
                  <div class="interest-onboarding__invitation-actions">
                    <DButton
                      @action={{fn
                        this.respondToLegacyBookmark
                        bookmark
                        "reconfirm"
                      }}
                      @label="where_is_my_friends.legacy_practice_bookmarks.reconfirm"
                      @icon="check"
                      @disabled={{this.loading}}
                      class="btn-primary"
                      data-test-reconfirm-legacy-practice={{bookmark.id}}
                    />
                    <DButton
                      @action={{fn
                        this.respondToLegacyBookmark
                        bookmark
                        "dismiss"
                      }}
                      @label="where_is_my_friends.legacy_practice_bookmarks.dismiss"
                      @disabled={{this.loading}}
                      class="btn-flat"
                      data-test-dismiss-legacy-practice={{bookmark.id}}
                    />
                  </div>
                {{else}}
                  <span class="interest-onboarding__invitation-status">
                    {{i18n
                      (concat
                        "where_is_my_friends.legacy_practice_bookmarks.status."
                        bookmark.state
                      )
                    }}
                  </span>
                {{/if}}
              </article>
            {{/each}}
          </div>
        </section>
      {{/if}}

      {{#if this.invitationTarget}}
        <section
          class="interest-onboarding__invitation-form"
          data-test-practice-invitation-form
        >
          <div>
            <p class="interest-onboarding__eyebrow">{{i18n
                "where_is_my_friends.practice_invitations.eyebrow"
              }}</p>
            <h2>{{i18n
                "where_is_my_friends.practice_invitations.form_title"
                username=this.invitationTarget.username
              }}</h2>
            <p>{{i18n
                "where_is_my_friends.practice_invitations.one_to_one_notice"
              }}</p>
          </div>

          <label>
            <span>{{i18n
                "where_is_my_friends.practice_invitations.interest"
              }}</span>
            <select
              value={{this.invitationInterestId}}
              data-test-practice-invitation-interest
              {{on "change" this.updateInvitationInterest}}
            >
              {{#each this.invitationInterests as |interest|}}
                <option value={{interest.id}}>{{interest.name}}</option>
              {{/each}}
            </select>
          </label>

          <label>
            <span>{{i18n
                "where_is_my_friends.practice_invitations.proposed_time"
              }}</span>
            <input
              type="datetime-local"
              value={{this.invitationProposedAt}}
              data-test-practice-invitation-time
              {{on "input" this.updateInvitationProposedAt}}
            />
          </label>

          <label>
            <span>{{i18n
                "where_is_my_friends.practice_invitations.note"
              }}</span>
            <textarea
              maxlength="500"
              value={{this.invitationNote}}
              data-test-practice-invitation-note
              {{on "input" this.updateInvitationNote}}
            ></textarea>
          </label>

          <p
            class="interest-onboarding__invitation-preview"
            data-test-practice-invitation-preview
          >
            {{this.invitationPreview}}
          </p>

          <div class="interest-onboarding__form-actions">
            <DButton
              @action={{this.sendInvitation}}
              @label="where_is_my_friends.practice_invitations.send"
              @icon="paper-plane"
              @disabled={{this.loading}}
              class="btn-primary"
              data-test-send-practice-invitation
            />
            <DButton
              @action={{this.closeInvitation}}
              @label="where_is_my_friends.practice_invitations.cancel"
              @disabled={{this.loading}}
              class="btn-flat"
              data-test-cancel-practice-invitation
            />
          </div>
        </section>
      {{/if}}

      {{#if this.incomingInvitations.length}}
        <section class="interest-onboarding__invitations">
          <h2>{{i18n
              "where_is_my_friends.practice_invitations.incoming"
            }}</h2>
          <div class="interest-onboarding__invitation-list">
            {{#each this.incomingInvitations as |invitation|}}
              <article data-test-incoming-invitation={{invitation.id}}>
                <h3>@{{invitation.sender.username}}</h3>
                <p>{{invitation.preset_message}}</p>
                {{#if invitation.proposed_at}}
                  <p>{{i18n
                      "where_is_my_friends.practice_invitations.proposed_time_value"
                      time=invitation.proposed_at
                    }}</p>
                {{/if}}
                {{#if invitation.note}}
                  <blockquote>{{invitation.note}}</blockquote>
                {{/if}}
                {{#if (eq invitation.status "pending")}}
                  <div class="interest-onboarding__invitation-actions">
                    <DButton
                      @action={{fn
                        this.respondToInvitation
                        invitation
                        "accept"
                      }}
                      @label="where_is_my_friends.practice_invitations.accept"
                      @icon="check"
                      @disabled={{this.loading}}
                      class="btn-primary"
                      data-test-accept-practice-invitation={{invitation.id}}
                    />
                    <DButton
                      @action={{fn
                        this.respondToInvitation
                        invitation
                        "decline"
                      }}
                      @label="where_is_my_friends.practice_invitations.decline"
                      @disabled={{this.loading}}
                      class="btn-default"
                      data-test-decline-practice-invitation={{invitation.id}}
                    />
                    <DButton
                      @action={{fn
                        this.respondToInvitation
                        invitation
                        "ignore"
                      }}
                      @label="where_is_my_friends.practice_invitations.ignore"
                      @disabled={{this.loading}}
                      class="btn-flat"
                      data-test-ignore-practice-invitation={{invitation.id}}
                    />
                  </div>
                {{else if invitation.pm_url}}
                  <a href={{invitation.pm_url}}>{{i18n
                      "where_is_my_friends.practice_invitations.open_pm"
                    }}</a>
                {{else}}
                  <span class="interest-onboarding__invitation-status">
                    {{i18n
                      (concat
                        "where_is_my_friends.practice_invitations.status."
                        invitation.status
                      )
                    }}
                  </span>
                {{/if}}
              </article>
            {{/each}}
          </div>
        </section>
      {{/if}}

      {{#if this.outgoingInvitations.length}}
        <details class="interest-onboarding__outgoing-invitations">
          <summary>{{i18n
              "where_is_my_friends.practice_invitations.outgoing"
            }}</summary>
          {{#each this.outgoingInvitations as |invitation|}}
            <p data-test-outgoing-invitation={{invitation.id}}>
              @{{invitation.recipient.username}} ·
              {{invitation.interest.name}}
              ·
              {{i18n
                (concat
                  "where_is_my_friends.practice_invitations.status."
                  invitation.status
                )
              }}
            </p>
          {{/each}}
        </details>
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
              <label class="interest-onboarding__search">
                <span>{{i18n
                    "where_is_my_friends.interests.search_label"
                  }}</span>
                <input
                  type="search"
                  value={{this.interestSearch}}
                  placeholder={{i18n
                    "where_is_my_friends.interests.search_placeholder"
                  }}
                  data-test-interest-search
                  {{on "input" this.updateInterestSearch}}
                />
              </label>

              {{#if this.interestGroups.length}}
                <div
                  class="interest-onboarding__interest-groups"
                  data-test-interest-options
                >
                  {{#each this.interestGroups as |group|}}
                    <section
                      class="interest-onboarding__interest-group"
                      data-test-interest-group={{group.key}}
                    >
                      <div>
                        <h3>{{group.name}}</h3>
                        {{#if group.description}}
                          <p>{{group.description}}</p>
                        {{/if}}
                      </div>
                      <div class="interest-onboarding__chips">
                        {{#each group.interests as |interest|}}
                          <DButton
                            @action={{fn
                              this.toggleInterest
                              interest.id
                            }}
                            @translatedLabel={{interest.name}}
                            @icon={{if interest.selected "check" "plus"}}
                            @disabled={{this.loading}}
                            class={{if
                              interest.selected
                              "btn-primary"
                              "btn-default"
                            }}
                            aria-pressed={{if
                              interest.selected
                              "true"
                              "false"
                            }}
                            data-test-interest={{interest.name}}
                          />
                        {{/each}}
                      </div>
                    </section>
                  {{/each}}
                </div>
              {{else}}
                <p
                  class="interest-onboarding__search-empty"
                  data-test-interest-search-empty
                >{{i18n
                    "where_is_my_friends.interests.search_empty"
                  }}</p>
              {{/if}}
              <p
                class="interest-onboarding__selection-count"
                data-test-interest-count
              >{{i18n
                  "where_is_my_friends.interests.selection_count"
                  count=this.selectedInterestIds.size
                  maximum=this.maximumInterests
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
                    {{#if
                      this.siteSettings.where_is_my_friends_practice_invitations_enabled
                    }}
                      {{#if user.invitation_interests.length}}
                        <DButton
                          @action={{fn this.openInvitation user}}
                          @label="where_is_my_friends.practice_invitations.invite"
                          @icon="user-plus"
                          @disabled={{this.loading}}
                          class="btn-primary"
                          data-test-invite-user={{user.id}}
                        />
                      {{/if}}
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
