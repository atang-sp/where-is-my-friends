import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import { createClientTelemetry } from "./client-telemetry";

export default class PreferenceRecommendationSession {
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
  @tracked interestSearch = "";

  constructor({
    model,
    currentUser,
    practiceInvitationsEnabled = false,
    transport = ajax,
    telemetry = createClientTelemetry(),
  }) {
    this.model = model;
    this.currentUser = currentUser;
    this.practiceInvitationsEnabled = practiceInvitationsEnabled;
    this.transport = transport;
    this.telemetry = telemetry;

    this.state = this.model.state;
    const visibleInterestIds = new Set(
      (this.model.catalogue ?? []).map((interest) => interest.id)
    );
    this.selectedInterestIds = new Set(
      (this.model.profile?.interests ?? [])
        .map((interest) => interest.id)
        .filter((interestId) => visibleInterestIds.has(interestId))
    );
    this.purpose = this.model.profile?.purpose ?? null;
    this.recommendable = this.model.profile?.recommendable ?? true;
    this.showInterestsPublicly =
      this.model.profile?.show_interests_publicly ?? false;
    this.recommendedTopics = this.model.recommended_topics ?? [];
    this.recommendedUsers = this.model.recommended_users ?? [];
    this.algorithmVersion = this.model.algorithm_version;
    this.editing = this.state !== "complete";

    this.intents = Object.freeze({
      initialize: this.initialize,
      edit: this.edit,
      editor: Object.freeze({
        save: this.save,
        selectPurpose: this.selectPurpose,
        skip: this.skip,
        toggleInterest: this.toggleInterest,
        updateInterestSearch: this.updateInterestSearch,
        updatePublicInterests: this.updatePublicInterests,
        updateRecommendable: this.updateRecommendable,
      }),
      results: Object.freeze({
        disablePersonalization: this.disablePersonalization,
        dismiss: this.dismiss,
        edit: this.edit,
        trackTopicOpen: this.trackTopicOpen,
        trackUserOpen: this.trackUserOpen,
      }),
    });
  }

  get view() {
    return {
      state: this.state,
      editing: this.editing,
      loading: this.loading,
      error: this.error,
      editor: this.editing ? this.editorState : null,
      results:
        !this.editing && this.state !== "dismissed" ? this.resultsState : null,
    };
  }

  get editorState() {
    return {
      canSave: this.canSave,
      catalogue: this.catalogue,
      interestGroups: this.interestGroups,
      interestSearch: this.interestSearch,
      loading: this.loading,
      maximumInterests: this.maximumInterests,
      purposeOptions: this.purposeOptions,
      recommendable: this.recommendable,
      selectedInterestIds: this.selectedInterestIds,
      showInterestsPublicly: this.showInterestsPublicly,
      state: this.state,
    };
  }

  get resultsState() {
    return {
      hasRecommendations: this.hasRecommendations,
      loading: this.loading,
      practiceInvitationsEnabled: this.practiceInvitationsEnabled,
      recommendedTopics: this.recommendedTopics,
      recommendedUsers: this.recommendedUsers,
    };
  }

  get catalogue() {
    return this.model.catalogue ?? [];
  }

  get purposeOptions() {
    return (this.model.purposes ?? []).map((purpose) => ({
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
    const configuredGroups = this.model.catalogue_groups ?? [];
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
        const selectedCount = interests.filter(
          (interest) => interest.selected
        ).length;
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
      this.model.selection_limits?.minimum ?? 3,
      this.catalogue.length
    );
  }

  get maximumInterests() {
    return this.model.selection_limits?.maximum ?? 5;
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

  @action
  initialize() {
    void this.telemetry.record("interest_onboarding_viewed");
    this.recordRecommendationImpressions();
  }

  @action
  toggleInterest(interestId) {
    const next = new Set(this.selectedInterestIds);
    if (next.has(interestId)) {
      next.delete(interestId);
    } else if (next.size < this.maximumInterests) {
      const entry = this.catalogue.find(
        (interest) => interest.id === interestId
      );
      const groupKey = entry?.group_key;
      const group = this.interestGroups.find(
        (interestGroup) => interestGroup.key === groupKey
      );

      if (group?.isSingle) {
        for (const groupInterest of group.interests) {
          next.delete(groupInterest.id);
        }
        next.add(interestId);
      } else if (group?.maxPerGroup != null) {
        const currentGroupCount = group.interests.filter((interest) =>
          next.has(interest.id)
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
      const response = await this.transport(
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
      const response = await this.transport(
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
      const response = await this.transport(
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
      const response = await this.transport(
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
    void this.telemetry.record("recommended_topic_opened", {
      surface: "interest_page",
      recommendationGroup: "topics",
      recommendation: topic,
      algorithmVersion: this.algorithmVersion,
      resultCount: this.recommendationResultCount,
    });
  }

  @action
  trackUserOpen(user) {
    void this.telemetry.record("recommended_user_opened", {
      surface: "interest_page",
      recommendationGroup: "people",
      recommendation: user,
      algorithmVersion: this.algorithmVersion,
      resultCount: this.recommendationResultCount,
    });
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
      void this.telemetry.record("recommendation_impression", {
        surface: "interest_page",
        recommendationGroup: "topics",
        recommendation,
        algorithmVersion: this.algorithmVersion,
        resultCount: this.recommendationResultCount,
      });
    }
    for (const recommendation of this.recommendedUsers) {
      void this.telemetry.record("recommendation_impression", {
        surface: "interest_page",
        recommendationGroup: "people",
        recommendation,
        algorithmVersion: this.algorithmVersion,
        resultCount: this.recommendationResultCount,
      });
    }
  }

  errorMessage(error) {
    const response = error?.jqXHR?.responseJSON ?? error?.responseJSON;
    return (
      response?.errors?.[0] ??
      i18n("where_is_my_friends.interests.generic_error")
    );
  }
}
