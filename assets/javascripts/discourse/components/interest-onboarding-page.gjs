import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import InterestOnboardingEditor from "./interest-onboarding-editor";
import InterestOnboardingInvitations from "./interest-onboarding-invitations";
import InterestOnboardingResults from "./interest-onboarding-results";

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
  @tracked algorithmVersion;
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
    this.algorithmVersion = this.args.model.algorithm_version;
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
      (interest) => !query || interest.name.toLocaleLowerCase().includes(query)
    );
    const configuredGroups = this.args.model.catalogue_groups ?? [];
    const fallbackGroups = [
      ...new Map(
        options.map((interest) => [
          interest.group_key ?? "community",
          {
            key: interest.group_key ?? "community",
            name:
              interest.group_name ??
              interest.group_key ??
              i18n("where_is_my_friends.interests.community_group"),
            description: "",
          },
        ])
      ).values(),
    ];

    return (configuredGroups.length ? configuredGroups : fallbackGroups)
      .map((group) => {
        const interests = options.filter(
          (interest) => interest.group_key === group.key
        );
        const selectedCount = interests.filter((i) => i.selected).length;
        const isSingle = group.selection_mode === "single";
        const maxPerGroup = isSingle ? 1 : group.max_per_group;
        const groupFull = maxPerGroup != null && selectedCount >= maxPerGroup;
        return {
          ...group,
          interests,
          selectedCount,
          isSingle,
          maxPerGroup,
          groupFull,
        };
      })
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

  get recommendationResultCount() {
    return this.recommendedTopics.length + this.recommendedUsers.length;
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

    return i18n("where_is_my_friends.practice_invitations.preset_message", {
      username: this.invitationTarget.username,
      interest: this.selectedInvitationInterest.name,
    });
  }

  @action
  async initialize() {
    void this.recordEvent("interest_onboarding_viewed");
    this.recordRecommendationImpressions();
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
      const entry = this.catalogue.find((i) => i.id === interestId);
      const groupKey = entry?.group_key;
      const group = this.interestGroups.find((g) => g.key === groupKey);

      if (group?.isSingle) {
        for (const gi of group.interests) {
          next.delete(gi.id);
        }
        next.add(interestId);
      } else if (group?.maxPerGroup != null) {
        const currentGroupCount = group.interests.filter((i) =>
          next.has(i.id)
        ).length;
        if (currentGroupCount < group.maxPerGroup) {
          next.add(interestId);
        }
      } else {
        next.add(interestId);
      }
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
  async dismiss(targetType, recommendation) {
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
          data: {
            target_type: targetType,
            target_id: recommendation.id,
            surface: "interest_page",
            candidate_source: recommendation.candidate_source,
            rank: recommendation.rank,
            algorithm_version: this.algorithmVersion,
          },
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
  trackTopicOpen(topic) {
    void this.recordEvent("recommended_topic_opened", topic, "topics");
  }

  @action
  trackUserOpen(user) {
    void this.recordEvent("recommended_user_opened", user, "people");
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
    if (this.loading || !this.invitationTarget || !this.invitationInterestId) {
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
    this.algorithmVersion = response.algorithm_version;
    this.updateCurrentUserState(response.state);
    this.recordRecommendationImpressions();
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

  recordRecommendationImpressions() {
    for (const recommendation of this.recommendedTopics) {
      void this.recordEvent(
        "recommendation_impression",
        recommendation,
        "topics"
      );
    }
    for (const recommendation of this.recommendedUsers) {
      void this.recordEvent(
        "recommendation_impression",
        recommendation,
        "people"
      );
    }
  }

  async recordEvent(
    eventName,
    recommendation = null,
    recommendationGroup = null
  ) {
    const data = { event_name: eventName };
    if (recommendation) {
      Object.assign(data, {
        surface: "interest_page",
        recommendation_group: recommendationGroup,
        candidate_source: recommendation.candidate_source,
        rank: recommendation.rank,
        algorithm_version: this.algorithmVersion,
        result_count: this.recommendationResultCount,
      });
    }

    try {
      await ajax("/where-is-my-friends/events.json", {
        type: "POST",
        data,
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
        <div class="alert alert-info" role="status" data-test-interest-loading>
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

      <InterestOnboardingInvitations
        @closeInvitation={{this.closeInvitation}}
        @incomingInvitations={{this.incomingInvitations}}
        @invitationInterestId={{this.invitationInterestId}}
        @invitationInterests={{this.invitationInterests}}
        @invitationNote={{this.invitationNote}}
        @invitationPreview={{this.invitationPreview}}
        @invitationProposedAt={{this.invitationProposedAt}}
        @invitationTarget={{this.invitationTarget}}
        @legacyPracticeBookmarks={{this.legacyPracticeBookmarks}}
        @loading={{this.loading}}
        @outgoingInvitations={{this.outgoingInvitations}}
        @respondToInvitation={{this.respondToInvitation}}
        @respondToLegacyBookmark={{this.respondToLegacyBookmark}}
        @sendInvitation={{this.sendInvitation}}
        @updateInvitationInterest={{this.updateInvitationInterest}}
        @updateInvitationNote={{this.updateInvitationNote}}
        @updateInvitationProposedAt={{this.updateInvitationProposedAt}}
      />
      {{#if this.editing}}
        <InterestOnboardingEditor
          @canSave={{this.canSave}}
          @catalogue={{this.catalogue}}
          @interestGroups={{this.interestGroups}}
          @interestSearch={{this.interestSearch}}
          @loading={{this.loading}}
          @maximumInterests={{this.maximumInterests}}
          @purposeOptions={{this.purposeOptions}}
          @recommendable={{this.recommendable}}
          @save={{this.save}}
          @selectPurpose={{this.selectPurpose}}
          @selectedInterestIds={{this.selectedInterestIds}}
          @showInterestsPublicly={{this.showInterestsPublicly}}
          @skip={{this.skip}}
          @state={{this.state}}
          @toggleInterest={{this.toggleInterest}}
          @updateInterestSearch={{this.updateInterestSearch}}
          @updatePublicInterests={{this.updatePublicInterests}}
          @updateRecommendable={{this.updateRecommendable}}
        />
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
        <InterestOnboardingResults
          @disablePersonalization={{this.disablePersonalization}}
          @dismiss={{this.dismiss}}
          @edit={{this.edit}}
          @hasRecommendations={{this.hasRecommendations}}
          @loading={{this.loading}}
          @openInvitation={{this.openInvitation}}
          @recommendedTopics={{this.recommendedTopics}}
          @recommendedUsers={{this.recommendedUsers}}
          @siteSettings={{this.siteSettings}}
          @trackTopicOpen={{this.trackTopicOpen}}
          @trackUserOpen={{this.trackUserOpen}}
        />
      {{/if}}
    </main>
  </template>
}
