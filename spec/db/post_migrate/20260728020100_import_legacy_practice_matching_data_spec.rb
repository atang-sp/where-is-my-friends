# frozen_string_literal: true
require Rails.root.join(
          "plugins/where-is-my-friends/db/post_migrate/20260728020100_import_legacy_practice_matching_data.rb"
        )

RSpec.describe ImportLegacyPracticeMatchingData do
  fab!(:recent_sender, :user)
  fab!(:recent_target, :user)
  fab!(:old_sender, :user)
  fab!(:old_target, :user)

  around do |example|
    created_legacy_table = false
    unless ActiveRecord::Base.connection.table_exists?(:practice_interests)
      ActiveRecord::Base
        .connection
        .create_table(:practice_interests) do |t|
          t.integer :user_id, null: false
          t.integer :target_user_id, null: false
          t.timestamps null: false
        end
      created_legacy_table = true
    end

    ActiveRecord::Migration.suppress_messages { example.run }
  ensure
    if created_legacy_table
      ActiveRecord::Base.connection.drop_table(
        :practice_interests,
        if_exists: true
      )
    end
  end

  it "imports recent intents as private reconfirmation bookmarks and all mutual pairs as silent history" do
    recent_forward =
      insert_legacy_interest(
        recent_sender,
        recent_target,
        created_at: 10.days.ago
      )
    insert_legacy_interest(recent_target, recent_sender, created_at: 9.days.ago)
    insert_legacy_interest(old_sender, old_target, created_at: 120.days.ago)
    insert_legacy_interest(old_target, old_sender, created_at: 119.days.ago)
    notification_count = Notification.count

    2.times { described_class.new.up }

    expect(
      WhereIsMyFriendsLegacyPracticeBookmark.order(:user_id).pluck(
        :user_id,
        :target_user_id,
        :state,
        :mutual_history
      )
    ).to contain_exactly(
      [recent_sender.id, recent_target.id, "needs_reconfirmation", true],
      [recent_target.id, recent_sender.id, "needs_reconfirmation", true]
    )
    expect(
      WhereIsMyFriendsLegacyPracticeBookmark.find_by!(
        user: recent_sender,
        target_user: recent_target
      ).source_practice_interest_id
    ).to eq(recent_forward)
    expect(
      WhereIsMyFriendsLegacyPracticePair.order(:user_a_id).pluck(
        :user_a_id,
        :user_b_id,
        :notification_suppressed
      )
    ).to contain_exactly(
      [recent_sender.id, recent_target.id, true],
      [old_sender.id, old_target.id, true]
    )
    expect(WhereIsMyFriendsPracticeInvitation.count).to eq(0)
    expect(Notification.count).to eq(notification_count)
  end

  private

  def insert_legacy_interest(user, target, created_at:)
    DB.query_single(
      <<~SQL,
        INSERT INTO practice_interests
          (user_id, target_user_id, created_at, updated_at)
        VALUES
          (:user_id, :target_user_id, :created_at, :created_at)
        RETURNING id
      SQL
      user_id: user.id,
      target_user_id: target.id,
      created_at: created_at
    ).first
  end
end
