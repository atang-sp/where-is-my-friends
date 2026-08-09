# frozen_string_literal: true

class SeedGoddessWorshipCatalogueTag < ActiveRecord::Migration[8.0]
  def up
    return unless Migration::Helpers.existing_site?

    execute <<~SQL
      INSERT INTO tags (name, created_at, updated_at)
      VALUES ('女神崇拜', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT (name) DO NOTHING
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
