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

# == Schema Information
#
# Table name: where_is_my_friends_interest_profiles
#
#  id                      :bigint           not null, primary key
#  completed_at            :datetime
#  dismissed_at            :datetime
#  personalization_enabled :boolean          default(TRUE), not null
#  purpose                 :string
#  recommendable           :boolean          default(TRUE), not null
#  show_interests_publicly :boolean          default(FALSE), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  user_id                 :integer          not null
#
# Indexes
#
#  idx_wimf_interest_profiles_user  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
