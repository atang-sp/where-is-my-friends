# frozen_string_literal: true

class PreservePracticeInvitationInterestHistory < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL
      UPDATE where_is_my_friends_practice_invitations invitations
      SET interest_name = tags.name
      FROM tags
      WHERE tags.id = invitations.tag_id
        AND invitations.interest_name IS NULL
    SQL
    change_column_null :where_is_my_friends_practice_invitations,
                       :interest_name,
                       false

    remove_foreign_key :where_is_my_friends_practice_invitations,
                       column: :tag_id
    change_column_null :where_is_my_friends_practice_invitations, :tag_id, true
    add_foreign_key :where_is_my_friends_practice_invitations,
                    :tags,
                    on_delete: :nullify
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
