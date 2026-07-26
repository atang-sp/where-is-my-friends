# frozen_string_literal: true

class WhereIsMyFriendsInterestProfile < ActiveRecord::Base
  PURPOSES = %w[learn share connect ask help browse].freeze

  belongs_to :user
  has_many :interests,
           -> { order(:position, :id) },
           class_name: "WhereIsMyFriendsUserInterest",
           foreign_key: :user_id,
           primary_key: :user_id,
           dependent: :delete_all,
           inverse_of: :profile
  has_many :dismissals,
           class_name: "WhereIsMyFriendsRecommendationDismissal",
           foreign_key: :user_id,
           primary_key: :user_id,
           dependent: :delete_all,
           inverse_of: :profile

  validates :user_id, uniqueness: true
  validates :purpose, inclusion: { in: PURPOSES }, allow_nil: true

  def state
    return "complete" if completed_at.present? && personalization_enabled?
    return "dismissed" if dismissed_at.present?

    "pending"
  end
end
