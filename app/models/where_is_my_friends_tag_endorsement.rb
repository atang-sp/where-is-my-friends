# frozen_string_literal: true

class WhereIsMyFriendsTagEndorsement < ActiveRecord::Base
  belongs_to :tag, class_name: "WhereIsMyFriendsUserTag"
  belongs_to :user

  validate :tag_must_be_approved
  validate :user_must_not_be_participant

  private

  def tag_must_be_approved
    errors.add(:tag, :invalid) unless tag&.approved?
  end

  def user_must_not_be_participant
    return if user_id.blank? || tag.blank?

    if user_id == tag.proposer_id || user_id == tag.target_user_id
      errors.add(:user_id, :invalid)
    end
  end
end

# == Schema Information
#
# Table name: where_is_my_friends_tag_endorsements
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  tag_id     :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  idx_wimf_tag_endorsements_tag_user  (tag_id,user_id) UNIQUE
#  idx_wimf_tag_endorsements_user      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (tag_id => where_is_my_friends_user_tags.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
