# frozen_string_literal: true

require_relative "base"

module WhereIsMyFriends
  class NextAction
    module Evaluators
      class Dynamic < Base
        def evaluate
          dynamic = recent_dynamic
          return unless dynamic

          action(
            :dynamic,
            primary_kind: :open_dynamic,
            primary_url: dynamic.fetch(:url)
          ).merge(recommendation_group: "dynamics")
        end

        def recent_dynamic
          unless SiteSetting.where_is_my_friends_dynamics_enabled &&
                   SiteSetting.where_is_my_friends_dynamics_feed_enabled
            return
          end

          DynamicFeed
            .new(viewer: user, guardian: guardian)
            .recent
            .fetch(:dynamics)
            .first
        rescue Discourse::NotFound
          nil
        end
      end
    end
  end
end
