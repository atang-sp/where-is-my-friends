# frozen_string_literal: true

class AddPracticeInvitationInterestName < ActiveRecord::Migration[7.0]
  def change
    add_column :where_is_my_friends_practice_invitations,
               :interest_name,
               :string
  end
end
