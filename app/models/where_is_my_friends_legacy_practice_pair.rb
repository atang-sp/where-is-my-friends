# frozen_string_literal: true

class WhereIsMyFriendsLegacyPracticePair < ActiveRecord::Base
  belongs_to :user_a, class_name: "User"
  belongs_to :user_b, class_name: "User"

  validates :user_b_id, uniqueness: { scope: :user_a_id }
  validate :participants_must_be_ordered

  private

  def participants_must_be_ordered
    if user_a_id.blank? || user_b_id.blank? || user_a_id >= user_b_id
      errors.add(:user_b_id, :invalid)
    end
  end
end

# == Schema Information
#
# Table name: where_is_my_friends_legacy_practice_pairs
#
#  id                      :bigint           not null, primary key
#  matched_at              :datetime         not null
#  notification_suppressed :boolean          default(TRUE), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  user_a_id               :integer          not null
#  user_b_id               :integer          not null
#
# Indexes
#
#  idx_wimf_legacy_pairs_unique  (user_a_id,user_b_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_a_id => users.id) ON DELETE => cascade
#  fk_rails_...  (user_b_id => users.id) ON DELETE => cascade
#
