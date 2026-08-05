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

# == Schema Information
#
# Table name: where_is_my_friends_recommendation_dismissals
#
#  id          :bigint           not null, primary key
#  target_type :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  target_id   :integer          not null
#  user_id     :integer          not null
#
# Indexes
#
#  idx_wimf_recommendation_dismissals_target  (target_type,target_id)
#  idx_wimf_recommendation_dismissals_unique  (user_id,target_type,target_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
