import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { scheduleOnce } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { createClientTelemetry } from "discourse/plugins/where-is-my-friends/discourse/lib/client-telemetry";

export default class CommunityDiscoveryPanel extends Component {
  @service currentUser;
  @service siteSettings;

  @tracked model = null;
  @tracked recentDynamics = [];
  @tracked dynamicsLoaded = false;
  @tracked loading = false;
  @tracked error = false;
  @tracked expanded = false;
  @tracked activeGroup = "topics";
  @tracked loadedGroups = new Set();

  refreshSequence = 0;
  telemetry = createClientTelemetry({ surface: "homepage" });

  get topics() {
    return (this.model?.recommended_topics ?? []).slice(0, 3);
  }

  get people() {
    return (this.model?.recommended_users ?? []).slice(0, 3).map((person) => ({
      ...person,
      primaryTopic: person.representative_topics?.[0] ?? null,
    }));
  }

  get interests() {
    return (this.model?.recommended_interests ?? []).slice(0, 2);
  }

  get dynamicsEnabled() {
    return (
      this.siteSettings.where_is_my_friends_dynamics_enabled &&
      this.siteSettings.where_is_my_friends_dynamics_homepage_enabled
    );
  }

  get topicsGroupCount() {
    return this.loadedGroups.has("topics") ? this.topics.length : "…";
  }

  get peopleGroupCount() {
    return this.loadedGroups.has("people") ? this.people.length : "…";
  }

  get interestsGroupCount() {
    return this.loadedGroups.has("interests") ? this.interests.length : "…";
  }

  get dynamicsGroupCount() {
    return this.dynamicsLoaded ? this.recentDynamics.length : "…";
  }

  get ownDynamicsUrl() {
    return `/u/${this.currentUser.username}/activity/dynamics`;
  }

  get resultCount() {
    return this.activeRecommendations.length;
  }

  get activeHasResults() {
    return this.activeRecommendations.length > 0;
  }

  get skeletonItems() {
    const count = this.activeGroup === "interests" ? 2 : 3;
    return Array.from({ length: count }, (_, index) => index);
  }

  get activeRecommendations() {
    return {
      topics: this.topics,
      people: this.people,
      interests: this.interests,
      dynamics: this.recentDynamics,
    }[this.activeGroup];
  }

  @action
  async toggle() {
    this.expanded = !this.expanded;
    void this.telemetry.record(
      this.expanded
        ? "recommendation_panel_expanded"
        : "recommendation_panel_collapsed",
      { recommendationGroup: this.activeGroup }
    );
    if (this.expanded) {
      if (this.loadedGroups.has(this.activeGroup)) {
        this.queueImpressions();
      } else {
        await this.loadRecommendations(null, this.activeGroup);
      }
    }
  }

  @action
  async refresh() {
    void this.telemetry.record("recommendation_refreshed", {
      recommendationGroup: this.activeGroup,
    });
    if (this.activeGroup === "dynamics") {
      await this.loadRecentDynamics(true);
      return;
    }
    this.refreshSequence += 1;
    await this.loadRecommendations(this.refreshSequence);
  }

  @action
  async selectGroup(group) {
    if (group === this.activeGroup) {
      return;
    }

    this.activeGroup = group;
    void this.telemetry.record("recommendation_group_selected", {
      recommendationGroup: group,
    });
    if (group === "dynamics") {
      if (this.dynamicsLoaded) {
        void this.telemetry.record("recent_dynamics_viewed", {
          recommendationGroup: "dynamics",
        });
      } else {
        await this.loadRecentDynamics();
      }
    } else if (!this.loadedGroups.has(group)) {
      await this.loadRecommendations(null, group);
    } else {
      this.queueImpressions();
    }
  }

  @action
  async dismiss(targetType, recommendation) {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this.error = false;
    let succeeded = false;
    try {
      const response = await ajax(
        "/where-is-my-friends/recommendations/dismiss.json",
        {
          type: "POST",
          data: {
            target_type: targetType,
            target_id: recommendation.id,
            group: this.activeGroup,
            surface: "homepage",
            candidate_source: recommendation.candidate_source,
            rank: recommendation.rank,
            algorithm_version: this.model?.algorithm_version,
          },
        }
      );
      this.model = { ...this.model, ...response };
      succeeded = true;
    } catch {
      this.error = true;
    } finally {
      this.loading = false;
    }
    if (succeeded) {
      this.queueImpressions();
    }
  }

  @action
  trackOpen(eventName, recommendation) {
    void this.telemetry.record(eventName, {
      recommendationGroup: this.activeGroup,
      recommendation,
      algorithmVersion: this.model?.algorithm_version,
      resultCount: this.resultCount,
    });
  }

  @action
  trackDynamicOpen(eventName, recommendation = null) {
    void this.telemetry.record(eventName, {
      recommendationGroup: "dynamics",
      recommendation,
    });
  }

  async loadRecommendations(refresh = null, group = this.activeGroup) {
    this.loading = true;
    this.error = false;
    let succeeded = false;
    try {
      const data = { group };
      if (refresh !== null) {
        data.refresh = refresh;
      }
      const response = await ajax("/where-is-my-friends/recommendations.json", {
        data,
      });
      this.model = { ...this.model, ...response };
      this.loadedGroups = new Set([...this.loadedGroups, group]);
      succeeded = true;
    } catch {
      this.error = true;
    } finally {
      this.loading = false;
    }
    if (succeeded) {
      this.queueImpressions();
    }
  }

  async loadRecentDynamics(force = false) {
    if (this.dynamicsLoaded && !force) {
      return;
    }

    this.loading = true;
    this.error = false;
    try {
      const result = await ajax("/where-is-my-friends/dynamics/recent.json");
      this.recentDynamics = (result.dynamics ?? []).slice(0, 3);
      this.dynamicsLoaded = true;
      void this.telemetry.record("recent_dynamics_viewed", {
        recommendationGroup: "dynamics",
      });
    } catch {
      this.error = true;
    } finally {
      this.loading = false;
    }
  }

  queueImpressions() {
    scheduleOnce("afterRender", this, this.recordImpressions);
  }

  recordImpressions() {
    if (
      !this.expanded ||
      this.loading ||
      !this.loadedGroups.has(this.activeGroup) ||
      this.activeGroup === "dynamics"
    ) {
      return;
    }

    for (const recommendation of this.activeRecommendations) {
      void this.telemetry.record("recommendation_impression", {
        recommendationGroup: this.activeGroup,
        recommendation,
        algorithmVersion: this.model?.algorithm_version,
        resultCount: this.resultCount,
      });
    }
  }

  <template>
    <section
      class={{if
        this.expanded
        "community-discovery community-discovery--expanded"
        "community-discovery community-discovery--collapsed"
      }}
      data-test-community-discovery
    >
      <header class="community-discovery__header">
        <div>
          <h2>{{i18n
              "where_is_my_friends.community_discovery.compact_title"
            }}</h2>
          <p>{{i18n
              "where_is_my_friends.community_discovery.compact_description"
            }}</p>
        </div>
        <DButton
          @action={{this.toggle}}
          @label={{if
            this.expanded
            "where_is_my_friends.community_discovery.collapse"
            "where_is_my_friends.community_discovery.expand"
          }}
          @icon={{if this.expanded "chevron-up" "chevron-down"}}
          @ariaExpanded={{this.expanded}}
          @ariaControls="community-discovery-content"
          class="btn-flat community-discovery__toggle"
          data-test-community-toggle
        />
      </header>

      {{#if this.expanded}}
        <div
          id="community-discovery-content"
          class="community-discovery__content"
          data-test-community-content
        >
          <div class="community-discovery__controls">
            <DButton
              @action={{this.refresh}}
              @label="where_is_my_friends.community_discovery.refresh"
              @icon="arrows-rotate"
              @disabled={{this.loading}}
              class="btn-flat"
              data-test-community-refresh
            />
          </div>
          {{#if this.loading}}
            <div
              class="community-discovery__grid community-discovery__skeleton-grid"
              role="status"
              aria-label={{i18n
                "where_is_my_friends.community_discovery.loading"
              }}
            >
              {{#each this.skeletonItems}}
                <article
                  class="community-discovery__skeleton"
                  aria-hidden="true"
                  data-test-community-skeleton
                >
                  <span></span>
                  <span></span>
                  <span></span>
                </article>
              {{/each}}
            </div>
          {{else if this.error}}
            <div
              class="community-discovery__error"
              role="status"
              data-test-community-error
            >
              <span>{{i18n
                  "where_is_my_friends.community_discovery.error"
                }}</span>
              <DButton
                @action={{this.refresh}}
                @label="where_is_my_friends.community_discovery.retry"
                class="btn-flat"
                data-test-community-retry
              />
            </div>
          {{else if this.model}}
            <nav
              class="community-discovery__groups"
              aria-label={{i18n
                "where_is_my_friends.community_discovery.groups_label"
              }}
              data-test-community-groups
            >
              <DButton
                @action={{fn this.selectGroup "topics"}}
                @translatedLabel={{i18n
                  "where_is_my_friends.community_discovery.topics_group"
                  count=this.topicsGroupCount
                }}
                @ariaPressed={{eq this.activeGroup "topics"}}
                class={{if
                  (eq this.activeGroup "topics")
                  "btn-primary community-discovery__group"
                  "btn-default community-discovery__group"
                }}
                data-test-community-group="topics"
              />
              <DButton
                @action={{fn this.selectGroup "people"}}
                @translatedLabel={{i18n
                  "where_is_my_friends.community_discovery.people_group"
                  count=this.peopleGroupCount
                }}
                @ariaPressed={{eq this.activeGroup "people"}}
                class={{if
                  (eq this.activeGroup "people")
                  "btn-primary community-discovery__group"
                  "btn-default community-discovery__group"
                }}
                data-test-community-group="people"
              />
              <DButton
                @action={{fn this.selectGroup "interests"}}
                @translatedLabel={{i18n
                  "where_is_my_friends.community_discovery.interests_group"
                  count=this.interestsGroupCount
                }}
                @ariaPressed={{eq this.activeGroup "interests"}}
                class={{if
                  (eq this.activeGroup "interests")
                  "btn-primary community-discovery__group"
                  "btn-default community-discovery__group"
                }}
                data-test-community-group="interests"
              />
              {{#if this.dynamicsEnabled}}
                <DButton
                  @action={{fn this.selectGroup "dynamics"}}
                  @translatedLabel={{i18n
                    "where_is_my_friends.community_discovery.dynamics_group"
                    count=this.dynamicsGroupCount
                  }}
                  @ariaPressed={{eq this.activeGroup "dynamics"}}
                  class={{if
                    (eq this.activeGroup "dynamics")
                    "btn-primary community-discovery__group"
                    "btn-default community-discovery__group"
                  }}
                  data-test-community-group="dynamics"
                />
              {{/if}}
            </nav>
            {{#if (eq this.activeGroup "topics")}}
              {{#if this.topics.length}}
                <section class="community-discovery__section">
                  <h3>{{i18n
                      "where_is_my_friends.community_discovery.topics_title"
                    }}</h3>
                  <div class="community-discovery__grid">
                    {{#each this.topics as |topic|}}
                      <article data-test-community-topic={{topic.id}}>
                        <a
                          href={{topic.url}}
                          data-test-community-topic-action
                          {{on
                            "click"
                            (fn this.trackOpen "recommended_topic_opened" topic)
                          }}
                        >
                          <h4>{{topic.fancy_title}}</h4>
                        </a>
                        <p data-test-community-topic-reason>
                          <strong>{{i18n
                              "where_is_my_friends.community_discovery.why"
                            }}</strong>
                          {{i18n
                            "where_is_my_friends.community_discovery.topic_reason"
                          }}
                          {{#each topic.matching_interests as |interest|}}
                            <span>{{interest.name}}</span>
                          {{/each}}
                        </p>
                        <p class="community-discovery__signal">
                          {{i18n
                            (concat
                              "where_is_my_friends.community_discovery.topic_state."
                              topic.participation_state
                            )
                          }}
                        </p>
                        <div class="community-discovery__actions">
                          <a
                            class="btn btn-primary"
                            href={{topic.url}}
                            {{on
                              "click"
                              (fn
                                this.trackOpen "recommended_topic_opened" topic
                              )
                            }}
                          >{{i18n
                              "where_is_my_friends.community_discovery.join_discussion"
                            }}</a>
                          <DButton
                            @action={{fn this.dismiss "topic" topic}}
                            @label="where_is_my_friends.interests.not_interested"
                            @disabled={{this.loading}}
                            class="btn-flat"
                            data-test-community-dismiss
                          />
                        </div>
                      </article>
                    {{/each}}
                  </div>
                </section>
              {{/if}}
            {{/if}}

            {{#if (eq this.activeGroup "dynamics")}}
              {{#if this.recentDynamics.length}}
                <section class="community-discovery__section">
                  <h3>{{i18n
                      "where_is_my_friends.community_discovery.dynamics_title"
                    }}</h3>
                  <div class="community-discovery__grid">
                    {{#each this.recentDynamics as |dynamic|}}
                      <article data-test-community-dynamic={{dynamic.id}}>
                        <div class="community-discovery__person-heading">
                          <h4>{{if
                              dynamic.author.name
                              dynamic.author.name
                              dynamic.author.username
                            }}</h4>
                          <span>@{{dynamic.author.username}}</span>
                        </div>
                        <p>{{dynamic.excerpt}}</p>
                        <div class="community-discovery__actions">
                          <a
                            class="btn btn-primary"
                            href={{dynamic.url}}
                            data-test-community-dynamic-open
                            {{on
                              "click"
                              (fn
                                this.trackDynamicOpen "dynamic_opened" dynamic
                              )
                            }}
                          >{{i18n
                              "where_is_my_friends.dynamics.open_and_reply"
                            }}</a>
                        </div>
                      </article>
                    {{/each}}
                  </div>
                </section>
              {{else}}
                <div
                  class="community-discovery__empty"
                  data-test-community-dynamics-empty
                >
                  <span>{{i18n
                      "where_is_my_friends.community_discovery.dynamics_empty"
                    }}</span>
                  <a class="btn btn-flat" href={{this.ownDynamicsUrl}}>{{i18n
                      "where_is_my_friends.community_discovery.share_dynamic"
                    }}</a>
                </div>
              {{/if}}
            {{/if}}

            {{#if (eq this.activeGroup "people")}}
              {{#if this.people.length}}
                <section class="community-discovery__section">
                  <h3>{{i18n
                      "where_is_my_friends.community_discovery.people_title"
                    }}</h3>
                  <div class="community-discovery__grid">
                    {{#each this.people as |person|}}
                      <article data-test-community-person={{person.username}}>
                        <div class="community-discovery__person-heading">
                          <h4>{{if
                              person.name
                              person.name
                              person.username
                            }}</h4>
                          <span>@{{person.username}}</span>
                        </div>
                        <p data-test-community-person-reason>
                          <strong>{{i18n
                              "where_is_my_friends.community_discovery.why"
                            }}</strong>
                          {{i18n
                            "where_is_my_friends.community_discovery.person_reason"
                          }}
                          {{#each person.reason_interests as |interest|}}
                            <span>{{interest.name}}</span>
                          {{/each}}
                        </p>
                        {{#if person.latest_dynamic}}
                          <a
                            class="community-discovery__dynamic-preview"
                            href={{person.latest_dynamic.url}}
                            data-test-community-person-dynamic
                            {{on
                              "click"
                              (fn
                                this.trackOpen
                                "recommended_user_dynamic_opened"
                                person
                              )
                            }}
                          >
                            <strong>{{i18n
                                "where_is_my_friends.community_discovery.latest_dynamic"
                              }}</strong>
                            {{person.latest_dynamic.excerpt}}
                          </a>
                        {{/if}}
                        <div class="community-discovery__actions">
                          {{#if person.primaryTopic}}
                            <a
                              class="btn btn-primary"
                              href={{person.primaryTopic.url}}
                              data-test-community-person-primary-action
                              {{on
                                "click"
                                (fn
                                  this.trackOpen
                                  "recommended_user_related_topic_opened"
                                  person
                                )
                              }}
                            >
                              {{i18n
                                "where_is_my_friends.community_discovery.join_person_discussion"
                              }}
                            </a>
                          {{/if}}
                          <a
                            class="btn btn-flat"
                            href={{person.profile_url}}
                            data-test-community-person-profile-action
                            {{on
                              "click"
                              (fn
                                this.trackOpen
                                "recommended_user_profile_opened"
                                person
                              )
                            }}
                          >
                            {{i18n
                              "where_is_my_friends.community_discovery.view_profile"
                            }}
                          </a>
                          {{#if person.invite_url}}
                            <a
                              class="btn btn-flat"
                              href={{person.invite_url}}
                              data-test-community-person-invite-action
                              {{on
                                "click"
                                (fn
                                  this.trackOpen
                                  "recommended_user_invite_started"
                                  person
                                )
                              }}
                            >
                              {{i18n
                                "where_is_my_friends.community_discovery.invite"
                              }}
                            </a>
                          {{/if}}
                          <DButton
                            @action={{fn this.dismiss "user" person}}
                            @label="where_is_my_friends.interests.not_interested"
                            @disabled={{this.loading}}
                            class="btn-flat"
                            data-test-community-dismiss
                          />
                        </div>
                      </article>
                    {{/each}}
                  </div>
                </section>
              {{/if}}
            {{/if}}

            {{#if (eq this.activeGroup "interests")}}
              {{#if this.interests.length}}
                <section class="community-discovery__section">
                  <h3>{{i18n
                      "where_is_my_friends.community_discovery.interests_title"
                    }}</h3>
                  <div
                    class="community-discovery__grid community-discovery__grid--interests"
                  >
                    {{#each this.interests as |interest|}}
                      <article data-test-community-interest={{interest.id}}>
                        <a
                          href={{interest.url}}
                          data-test-community-interest-action
                          {{on
                            "click"
                            (fn
                              this.trackOpen
                              "recommended_interest_opened"
                              interest
                            )
                          }}
                        >
                          <h4>{{interest.name}}</h4>
                        </a>
                        <p data-test-community-interest-reason>
                          <strong>{{i18n
                              "where_is_my_friends.community_discovery.why"
                            }}</strong>
                          {{#if interest.reason_interest}}
                            {{i18n
                              "where_is_my_friends.community_discovery.exploration_reason"
                              from=interest.reason_interest.name
                              to=interest.name
                            }}
                          {{else}}
                            {{#if interest.active_member_count_suppressed}}
                              {{i18n
                                "where_is_my_friends.community_discovery.interest_reason_private"
                                topicCount=interest.topic_count
                                newCount=interest.new_topic_count
                              }}
                            {{else}}
                              {{i18n
                                "where_is_my_friends.community_discovery.interest_reason"
                                topicCount=interest.topic_count
                                newCount=interest.new_topic_count
                                memberCount=interest.active_member_count
                              }}
                            {{/if}}
                          {{/if}}
                        </p>
                        <div class="community-discovery__actions">
                          <a
                            class="btn btn-primary"
                            href={{interest.url}}
                            {{on
                              "click"
                              (fn
                                this.trackOpen
                                "recommended_interest_opened"
                                interest
                              )
                            }}
                          >
                            {{i18n
                              "where_is_my_friends.community_discovery.explore"
                            }}
                          </a>
                          <DButton
                            @action={{fn this.dismiss "interest" interest}}
                            @label="where_is_my_friends.interests.not_interested"
                            @disabled={{this.loading}}
                            class="btn-flat"
                            data-test-community-dismiss
                          />
                        </div>
                      </article>
                    {{/each}}
                  </div>
                </section>
              {{/if}}
            {{/if}}
            {{#unless (eq this.activeGroup "dynamics")}}
              {{#unless this.activeHasResults}}
                <div
                  class="community-discovery__empty"
                  data-test-community-empty
                >
                  <p>{{i18n
                      "where_is_my_friends.community_discovery.empty"
                    }}</p>
                  <a
                    class="btn btn-primary"
                    href="/where-is-my-friends/interests"
                  >{{i18n "where_is_my_friends.interests.edit"}}</a>
                </div>
              {{/unless}}
            {{/unless}}
          {{else}}
            {{#unless this.loading}}
              <div class="community-discovery__empty" data-test-community-empty>
                <p>{{i18n "where_is_my_friends.community_discovery.empty"}}</p>
                <a
                  class="btn btn-primary"
                  href="/where-is-my-friends/interests"
                >{{i18n "where_is_my_friends.interests.edit"}}</a>
              </div>
            {{/unless}}
          {{/if}}
        </div>
      {{/if}}
    </section>
  </template>
}
