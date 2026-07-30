# frozen_string_literal: true

class WhereIsMyFriendsRecommendationDismissal < ActiveRecord::Base
  TARGET_TYPES = %w[topic user interest].freeze

  belongs_to :user
  belongs_to :profile,
             class_name: "WhereIsMyFriendsInterestProfile",
             foreign_key: :user_id,
             primary_key: :user_id,
             inverse_of: :dismissals

  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :target_id, uniqueness: { scope: %i[user_id target_type] }
end
