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
