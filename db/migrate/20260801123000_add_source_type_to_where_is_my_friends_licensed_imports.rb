# frozen_string_literal: true

class AddSourceTypeToWhereIsMyFriendsLicensedImports < ActiveRecord::Migration[
  7.2
]
  ACTIVE_STATUSES = "status IN ('processing', 'preview', 'published')"

  def up
    add_column :where_is_my_friends_licensed_imports,
               :source_type,
               :string,
               null: false,
               default: "stack_exchange"
    remove_index :where_is_my_friends_licensed_imports,
                 name: "idx_wimf_licensed_import_source_active"
    add_index :where_is_my_friends_licensed_imports,
              %i[source_type source_question_id],
              unique: true,
              where: ACTIVE_STATUSES,
              name: "idx_wimf_licensed_import_source_active"
  end

  def down
    remove_index :where_is_my_friends_licensed_imports,
                 name: "idx_wimf_licensed_import_source_active"
    add_index :where_is_my_friends_licensed_imports,
              :source_question_id,
              unique: true,
              where: ACTIVE_STATUSES,
              name: "idx_wimf_licensed_import_source_active"
    remove_column :where_is_my_friends_licensed_imports, :source_type
  end
end
