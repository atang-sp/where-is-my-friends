# frozen_string_literal: true

class AddRecommendationContextToWhereIsMyFriendsEvents < ActiveRecord::Migration[
  7.0
]
  def change
    add_column :where_is_my_friends_events, :surface, :string
    add_column :where_is_my_friends_events, :candidate_source, :string
    add_column :where_is_my_friends_events, :rank_bucket, :string
    add_column :where_is_my_friends_events, :algorithm_version, :string

    add_index :where_is_my_friends_events,
              %i[event_name surface created_at],
              name: "index_wimf_events_on_name_surface_created_at"
  end
end
