# frozen_string_literal: true

class WhereIsMyFriendsLegacyPracticeBookmark < ActiveRecord::Base
  STATES = %w[needs_reconfirmation reconfirmed dismissed].freeze

  belongs_to :user
  belongs_to :target_user, class_name: "User"

  validates :state, inclusion: { in: STATES }
  validates :target_user_id, uniqueness: { scope: :user_id }
  validate :participants_must_be_distinct

  scope :recent_first, -> { order(source_created_at: :desc, id: :desc) }

  private

  def participants_must_be_distinct
    if user_id.present? && user_id == target_user_id
      errors.add(:target_user_id, :invalid)
    end
  end
end

# == Schema Information
#
# Table name: where_is_my_friends_legacy_practice_bookmarks
#
#  id                          :bigint           not null, primary key
#  confirmed_at                :datetime
#  dismissed_at                :datetime
#  mutual_history              :boolean          default(FALSE), not null
#  source_created_at           :datetime
#  state                       :string           default("needs_reconfirmation"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  source_practice_interest_id :bigint
#  target_user_id              :integer          not null
#  user_id                     :integer          not null
#
# Indexes
#
#  idx_wimf_legacy_bookmarks_unique      (user_id,target_user_id) UNIQUE
#  idx_wimf_legacy_bookmarks_user_state  (user_id,state)
#
# Foreign Keys
#
#  fk_rails_...  (target_user_id => users.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
