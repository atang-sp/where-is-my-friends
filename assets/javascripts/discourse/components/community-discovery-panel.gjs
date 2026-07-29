import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class CommunityDiscoveryPanel extends Component {
  @tracked model = null;
  @tracked loading = true;
  @tracked error = false;

  refreshSequence = 0;

  constructor() {
    super(...arguments);
    void this.loadRecommendations();
  }

  get topics() {
    return (this.model?.recommended_topics ?? []).slice(0, 3);
  }

  get people() {
    return (this.model?.recommended_users ?? []).slice(0, 3);
  }

  get interests() {
    return (this.model?.recommended_interests ?? []).slice(0, 2);
  }

  get resultCount() {
    return this.topics.length + this.people.length + this.interests.length;
  }

  get hasResults() {
    return this.resultCount > 0;
  }

  @action
  async refresh() {
    this.refreshSequence += 1;
    await this.loadRecommendations(this.refreshSequence);
  }

  @action
  async dismiss(targetType, recommendation) {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this.error = false;
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
      this.recordImpressions();
    } catch {
      this.error = true;
    } finally {
      this.loading = false;
    }
  }

  @action
  trackOpen(eventName, recommendation) {
    void this.recordEvent(eventName, recommendation);
  }

  async loadRecommendations(refresh = null) {
    this.loading = true;
    this.error = false;
    try {
      const options = refresh === null ? {} : { data: { refresh } };
      this.model = await ajax(
        "/where-is-my-friends/recommendations.json",
        options
      );
      this.recordImpressions();
    } catch {
      this.error = true;
    } finally {
      this.loading = false;
    }
  }

  recordImpressions() {
    const recommendations = [
      ...this.topics,
      ...this.people,
      ...this.interests,
    ];
    for (const recommendation of recommendations) {
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
      class="community-discovery"
      data-test-community-discovery
    >
      <header class="community-discovery__header">
        <div>
          <p class="community-discovery__eyebrow">{{i18n
              "where_is_my_friends.community_discovery.eyebrow"
            }}</p>
          <h2>{{i18n "where_is_my_friends.community_discovery.title"}}</h2>
          <p>{{i18n "where_is_my_friends.community_discovery.description"}}</p>
        </div>
        <DButton
          @action={{this.refresh}}
          @label="where_is_my_friends.community_discovery.refresh"
          @icon="arrows-rotate"
          @disabled={{this.loading}}
          class="btn-flat"
          data-test-community-refresh
        />
      </header>

      {{#if this.error}}
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
          />
        </div>
      {{else if this.hasResults}}
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

        {{#if this.people.length}}
          <section class="community-discovery__section">
            <h3>{{i18n
                "where_is_my_friends.community_discovery.people_title"
              }}</h3>
            <div class="community-discovery__grid">
              {{#each this.people as |person|}}
                <article data-test-community-person={{person.username}}>
                  <a
                    href={{person.profile_url}}
                    data-test-community-person-action
                    {{on
                      "click"
                      (fn
                        this.trackOpen
                        "recommended_user_profile_opened"
                        person
                      )
                    }}
                  >
                    <h4>{{if person.name person.name person.username}}</h4>
                    <span>@{{person.username}}</span>
                  </a>
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
                  {{#if person.representative_topics.length}}
                    <ul>
                      {{#each person.representative_topics as |topic|}}
                        <li>
                          <a
                            href={{topic.url}}
                            data-test-community-person-topic-action
                            {{on
                              "click"
                              (fn
                                this.trackOpen
                                "recommended_user_related_topic_opened"
                                person
                              )
                            }}
                          >{{topic.title}}</a>
                        </li>
                      {{/each}}
                    </ul>
                  {{/if}}
                  <div class="community-discovery__actions">
                    <a
                      class="btn btn-default"
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
                        class="btn btn-primary"
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
      {{else}}
        {{#unless this.loading}}
          <div class="community-discovery__empty">
            <p>{{i18n "where_is_my_friends.community_discovery.empty"}}</p>
            <a
              class="btn btn-primary"
              href="/where-is-my-friends/interests"
            >{{i18n "where_is_my_friends.interests.edit"}}</a>
          </div>
        {{/unless}}
      {{/if}}
    </section>
  </template>
}
