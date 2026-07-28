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
