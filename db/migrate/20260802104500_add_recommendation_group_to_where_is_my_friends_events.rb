# frozen_string_literal: true

class AddRecommendationGroupToWhereIsMyFriendsEvents < ActiveRecord::Migration[
  7.0
]
  def change
    add_column :where_is_my_friends_events, :recommendation_group, :string

    add_index :where_is_my_friends_events,
              %i[event_name surface recommendation_group created_at],
              name: "index_wimf_events_on_name_surface_group_created_at"
  end
end
