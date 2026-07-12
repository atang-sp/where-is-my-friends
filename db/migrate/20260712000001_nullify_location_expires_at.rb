# frozen_string_literal: true

class NullifyLocationExpiresAt < ActiveRecord::Migration[7.0]
  def up
    execute "UPDATE user_locations SET expires_at = NULL"
  end

  def down
    execute <<~SQL
      UPDATE user_locations
      SET expires_at = updated_at + INTERVAL '30 days'
      WHERE expires_at IS NULL
    SQL
  end
end
