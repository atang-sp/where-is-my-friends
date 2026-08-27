# frozen_string_literal: true

class WhereIsMyFriendsDynamicReaction < ActiveRecord::Base
  KINDS = %w[relate curious open_to_chat support].freeze

  belongs_to :topic
  belongs_to :user
  belongs_to :notification, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :user_id, uniqueness: { scope: :topic_id }
  validate :topic_must_be_dynamic
  validate :user_must_not_be_author

  private

  def topic_must_be_dynamic
    unless WhereIsMyFriends::DynamicFeed.dynamic?(topic)
      errors.add(:topic, :invalid)
    end
  end

  def user_must_not_be_author
    return if user_id.blank? || topic.blank?

    errors.add(:user_id, :invalid) if user_id == topic.user_id
  end
end

# == Schema Information
#
# Table name: where_is_my_friends_dynamic_reactions
#
#  id              :bigint           not null, primary key
#  kind            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  notification_id :bigint
#  topic_id        :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  idx_wimf_dynamic_reactions_notification  (notification_id) UNIQUE
#  idx_wimf_dynamic_reactions_topic_user    (topic_id,user_id) UNIQUE
#  idx_wimf_dynamic_reactions_user          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (notification_id => notifications.id) ON DELETE => nullify
#  fk_rails_...  (topic_id => topics.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
