import { ajax } from "discourse/lib/ajax";

const EVENT_NAMES = new Set([
  "page_view",
  "directory_viewed",
  "setup_started",
  "city_previewed",
  "radius_confirmed",
  "location_saved",
  "results_viewed",
  "profile_clicked",
  "message_started",
  "local_topics_clicked",
  "local_topic_opened",
  "local_topic_interacted",
  "notification_opened",
  "location_removed",
  "interest_prompt_viewed",
  "interest_onboarding_viewed",
  "interest_onboarding_completed",
  "interest_onboarding_skipped",
  "recommended_topic_opened",
  "recommended_user_opened",
  "recommended_user_profile_opened",
  "recommended_user_related_topic_opened",
  "recommended_user_invite_started",
  "recommended_interest_opened",
  "recommendation_impression",
  "recommendation_dismissed",
  "recommendation_panel_expanded",
  "recommendation_panel_collapsed",
  "recommendation_group_selected",
  "recommendation_refreshed",
  "local_callout_viewed",
  "local_callout_opened",
  "local_callout_dismissed",
  "local_callout_location_saved",
  "personalization_disabled",
  "dynamics_profile_viewed",
  "recent_dynamics_viewed",
  "dynamic_opened",
  "recommended_user_dynamic_opened",
]);

const CONTEXT_FIELDS = {
  surface: "surface",
  recommendationGroup: "recommendation_group",
  candidateSource: "candidate_source",
  rank: "rank",
  algorithmVersion: "algorithm_version",
  resultCount: "result_count",
  locationMode: "location_mode",
  hasDynamicPreview: "has_dynamic_preview",
};

class ClientTelemetry {
  constructor(baseContext, transport) {
    this.baseContext = baseContext;
    this.transport = transport;
  }

  async record(eventName, eventContext = {}) {
    if (!EVENT_NAMES.has(eventName)) {
      return false;
    }

    const context = { ...this.baseContext, ...eventContext };
    const recommendation = context.recommendation;
    if (recommendation) {
      context.candidateSource ??= recommendation.candidate_source;
      context.rank ??= recommendation.rank;
      if (context.recommendationGroup === "people") {
        context.hasDynamicPreview ??= Boolean(recommendation.latest_dynamic);
      }
    }

    const data = { event_name: eventName };
    for (const [contextKey, payloadKey] of Object.entries(CONTEXT_FIELDS)) {
      if (context[contextKey] !== undefined && context[contextKey] !== null) {
        data[payloadKey] = context[contextKey];
      }
    }

    try {
      await this.transport("/where-is-my-friends/events.json", {
        type: "POST",
        data,
      });
      return true;
    } catch {
      return false;
    }
  }
}

export function createClientTelemetry(baseContext = {}, transport = ajax) {
  return new ClientTelemetry(baseContext, transport);
}
