# frozen_string_literal: true

class ImportLegacyPracticeMatchingData < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:practice_interests)

    import_recent_bookmarks
    import_mutual_pair_history
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def import_recent_bookmarks
    execute <<~SQL
      INSERT INTO where_is_my_friends_legacy_practice_bookmarks (
        user_id,
        target_user_id,
        source_practice_interest_id,
        source_created_at,
        state,
        mutual_history,
        created_at,
        updated_at
      )
      SELECT
        interest.user_id,
        interest.target_user_id,
        interest.id,
        interest.created_at,
        'needs_reconfirmation',
        EXISTS (
          SELECT 1
          FROM practice_interests reciprocal
          WHERE reciprocal.user_id = interest.target_user_id
            AND reciprocal.target_user_id = interest.user_id
        ),
        NOW(),
        NOW()
      FROM practice_interests interest
      INNER JOIN users owner ON owner.id = interest.user_id
      INNER JOIN users target ON target.id = interest.target_user_id
      WHERE interest.created_at >= NOW() - INTERVAL '90 days'
        AND interest.user_id <> interest.target_user_id
      ON CONFLICT (user_id, target_user_id) DO NOTHING
    SQL
  end

  def import_mutual_pair_history
    execute <<~SQL
      INSERT INTO where_is_my_friends_legacy_practice_pairs (
        user_a_id,
        user_b_id,
        matched_at,
        notification_suppressed,
        created_at,
        updated_at
      )
      SELECT
        forward.user_id,
        forward.target_user_id,
        GREATEST(forward.created_at, reciprocal.created_at),
        TRUE,
        NOW(),
        NOW()
      FROM practice_interests forward
      INNER JOIN practice_interests reciprocal
        ON reciprocal.user_id = forward.target_user_id
        AND reciprocal.target_user_id = forward.user_id
      INNER JOIN users user_a ON user_a.id = forward.user_id
      INNER JOIN users user_b ON user_b.id = forward.target_user_id
      WHERE forward.user_id < forward.target_user_id
      ON CONFLICT (user_a_id, user_b_id) DO NOTHING
    SQL
  end
end
