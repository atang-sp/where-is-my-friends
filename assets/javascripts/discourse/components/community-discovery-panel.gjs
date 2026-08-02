import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { scheduleOnce } from "@ember/runloop";
import { ajax } from "discourse/lib/ajax";
import { eq } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class CommunityDiscoveryPanel extends Component {
  @tracked model = null;
  @tracked loading = false;
  @tracked error = false;
  @tracked expanded = false;
  @tracked activeGroup = "topics";

  refreshSequence = 0;

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

  get resultCount() {
    return this.topics.length + this.people.length + this.interests.length;
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
    }[this.activeGroup];
  }

  @action
  async toggle() {
    this.expanded = !this.expanded;
    if (this.expanded) {
      if (this.model) {
        this.queueImpressions();
      } else {
        await this.loadRecommendations();
      }
    }
  }

  @action
  async refresh() {
    this.refreshSequence += 1;
    await this.loadRecommendations(this.refreshSequence);
  }

  @action
  selectGroup(group) {
    if (group === this.activeGroup) {
      return;
    }

    this.activeGroup = group;
    this.queueImpressions();
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
      this.model = await ajax(
        "/where-is-my-friends/recommendations/dismiss.json",
        {
          type: "POST",
          data: {
            target_type: targetType,
            target_id: recommendation.id,
            surface: "homepage",
            candidate_source: recommendation.candidate_source,
            rank: recommendation.rank,
            algorithm_version: this.model?.algorithm_version,
          },
        }
      );
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
    void this.recordEvent(eventName, recommendation);
  }

  async loadRecommendations(refresh = null) {
    this.loading = true;
    this.error = false;
    let succeeded = false;
    try {
      const options = refresh === null ? {} : { data: { refresh } };
      this.model = await ajax(
        "/where-is-my-friends/recommendations.json",
        options
      );
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

  queueImpressions() {
    scheduleOnce("afterRender", this, this.recordImpressions);
  }

  recordImpressions() {
    if (!this.expanded || this.loading || !this.model) {
      return;
    }

    for (const recommendation of this.activeRecommendations) {
      void this.recordEvent("recommendation_impression", recommendation);
    }
  }

  async recordEvent(eventName, recommendation) {
    try {
      await ajax("/where-is-my-friends/events.json", {
        type: "POST",
        data: {
          event_name: eventName,
          surface: "homepage",
          candidate_source: recommendation.candidate_source,
          rank: recommendation.rank,
          algorithm_version: this.model?.algorithm_version,
          result_count: this.resultCount,
        },
      });
    } catch {
      // Measurement must never block community discovery.
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
              count=this.topics.length
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
              count=this.people.length
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
              count=this.interests.length
            }}
            @ariaPressed={{eq this.activeGroup "interests"}}
            class={{if
              (eq this.activeGroup "interests")
              "btn-primary community-discovery__group"
              "btn-default community-discovery__group"
            }}
            data-test-community-group="interests"
          />
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
                        (fn this.trackOpen "recommended_topic_opened" topic)
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
                    <h4>{{if person.name person.name person.username}}</h4>
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
            <div class="community-discovery__grid community-discovery__grid--interests">
              {{#each this.interests as |interest|}}
                <article data-test-community-interest={{interest.id}}>
                  <a
                    href={{interest.url}}
                    data-test-community-interest-action
                    {{on
                      "click"
                      (fn this.trackOpen "recommended_interest_opened" interest)
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
        {{#unless this.activeHasResults}}
          <div
            class="community-discovery__empty"
            data-test-community-empty
          >
            <p>{{i18n "where_is_my_friends.community_discovery.empty"}}</p>
            <a
              class="btn btn-primary"
              href="/where-is-my-friends/interests"
            >{{i18n "where_is_my_friends.interests.edit"}}</a>
          </div>
        {{/unless}}
      {{else}}
        {{#unless this.loading}}
          <div
            class="community-discovery__empty"
            data-test-community-empty
          >
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
