# frozen_string_literal: true

require_relative "base"

module WhereIsMyFriends
  class NextAction
    module Evaluators
      class Recommendation < Base
        def evaluate
          profile = recommendation_profile
          return unless profile

          if recent_public_interaction?
            person = recommended_person(profile)
            return person_action(person) if person

            topic = recommended_topic(profile)
            topic_action(topic) if topic
          else
            topic = recommended_topic(profile)
            return topic_action(topic) if topic

            person = recommended_person(profile)
            person_action(person) if person
          end
        end

        def recommendation_profile
          return @recommendation_profile if defined?(@recommendation_profile)

          @recommendation_profile =
            if SiteSetting.where_is_my_friends_interest_onboarding_enabled
              WhereIsMyFriendsInterestProfile.find_by(
                user_id: user.id,
                personalization_enabled: true,
                completed_at: ..as_of
              )
            end
        end

        def recent_public_interaction?
          public_topic_ids =
            Topic
              .where(archetype: Archetype.default, visible: true, deleted_at: nil)
              .where(
                "topics.category_id IS NULL OR topics.category_id IN (" \
                  "SELECT categories.id FROM categories " \
                  "WHERE categories.read_restricted = FALSE)"
              )
              .select(:id)

          Post
            .where(
              user_id: user.id,
              topic_id: public_topic_ids,
              post_type: Post.types[:regular],
              created_at: (as_of - 30.days)..as_of,
              deleted_at: nil,
              hidden: false
            )
            .visible
            .exists?
        end

        def recommended_topic(profile = recommendation_profile)
          return unless profile

          topics =
            recommendation_engine
              .call(profile: profile, group: "topics")
              .fetch(:recommended_topics)
              .reject { |topic| topic.fetch(:viewer_replied, false) }
          topics.min_by do |topic|
            [
              topic_participation_priority(topic[:participation_state]),
              topic[:rank]
            ]
          end
        end

        def recommended_person(profile = recommendation_profile)
          return unless profile

          recommendation_engine.first_recommended_user(profile: profile)
        end

        private

        def recommendation_engine
          @recommendation_engine ||=
            RecommendationEngine.new(user, guardian: guardian)
        end

        def topic_participation_priority(state)
          { "awaiting_response" => 0, "unread" => 1, "active" => 2 }.fetch(state, 3)
        end

        def topic_action(topic)
          action(
            :topic,
            primary_kind: :open_topic,
            primary_url: topic.fetch(:url)
          ).merge(
            secondary_action: {
              kind: "open_recommendations",
              label_key: "where_is_my_friends.first_connection.more",
              url: "/where-is-my-friends/interests"
            },
            recommendation_group: "topics"
          )
        end

        def person_action(person)
          representative_topic = person.fetch(:representative_topics).first
          if representative_topic
            kind = :open_person_topic
            label_key = "where_is_my_friends.first_connection.person.topic_cta"
            url = representative_topic.fetch(:url)
          else
            kind = :open_person_profile
            label_key = "where_is_my_friends.first_connection.person.profile_cta"
            url = person.fetch(:profile_url)
          end

          action(
            :person,
            primary_kind: kind,
            primary_label_key: label_key,
            primary_url: url
          ).merge(
            secondary_action: {
              kind: "open_recommendations",
              label_key: "where_is_my_friends.first_connection.more_people",
              url: "/where-is-my-friends/interests"
            },
            recommendation_group: "people"
          )
        end
      end
    end
  end
end
