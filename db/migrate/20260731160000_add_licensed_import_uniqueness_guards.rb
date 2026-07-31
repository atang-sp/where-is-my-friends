# frozen_string_literal: true

class AddLicensedImportUniquenessGuards < ActiveRecord::Migration[7.0]
  ACTIVE_STATUSES = "status IN ('processing', 'preview', 'published')"

  def change
    add_column :where_is_my_friends_licensed_imports, :scheduled_for_date, :date
    add_index :where_is_my_friends_licensed_imports,
              :scheduled_for_date,
              unique: true,
              where: ACTIVE_STATUSES,
              name: "idx_wimf_licensed_import_daily_active"
    add_index :where_is_my_friends_licensed_imports,
              :source_question_id,
              unique: true,
              where: ACTIVE_STATUSES,
              name: "idx_wimf_licensed_import_source_active"
  end
end
