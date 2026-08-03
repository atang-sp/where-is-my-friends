# frozen_string_literal: true

class AddDynamicPreviewToWhereIsMyFriendsEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :where_is_my_friends_events, :has_dynamic_preview, :boolean

    add_index :where_is_my_friends_events,
              %i[event_name has_dynamic_preview created_at],
              name: "index_wimf_events_on_name_dynamic_preview_created_at"
  end
end
