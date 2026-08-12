# frozen_string_literal: true

class WhereIsMyFriendsUserTag < ActiveRecord::Base
  STATUSES = %w[pending approved rejected removed].freeze

  belongs_to :proposer, class_name: "User"
  belongs_to :target_user, class_name: "User"
  has_many :endorsements,
           class_name: "WhereIsMyFriendsTagEndorsement",
           foreign_key: :tag_id,
           dependent: :delete_all

  before_validation :clean_label

  validates :label,
            presence: true,
            length: {
              maximum: ->(_record) { WhereIsMyFriendsUserTag.max_label_length }
            }
  validates :status, inclusion: { in: STATUSES }
  validate :participants_must_be_distinct

  scope :pending_first, -> { order(status: :asc, created_at: :desc, id: :desc) }
  scope :for_target, ->(user) { where(target_user_id: user.id) }
  scope :by_proposer, ->(user) { where(proposer_id: user.id) }
  scope :approved, -> { where(status: "approved") }
  scope :approved_for_visibility,
        ->(viewer_id) do
          where(status: "approved").where.not(proposer_id: viewer_id)
        end

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def approve!
    return false unless pending?

    update!(status: "approved", responded_at: Time.current)
  end

  def reject!
    return false unless pending?

    update!(status: "rejected", responded_at: Time.current)
  end

  def remove!
    return false unless approved?

    update!(status: "removed", responded_at: Time.current)
  end

  def self.max_label_length
    SiteSetting.where_is_my_friends_user_tag_max_length.to_i.clamp(1, 50)
  end

  private

  def clean_label
    self.label = label.to_s.strip.gsub(/\s+/, " ").presence
  end

  def participants_must_be_distinct
    if proposer_id.present? && proposer_id == target_user_id
      errors.add(:target_user_id, :invalid)
    end
  end
end

# == Schema Information
#
# Table name: where_is_my_friends_user_tags
#
#  id            :bigint           not null, primary key
#  label         :string           not null
#  responded_at  :datetime
#  status        :string           default("pending"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  proposer_id   :integer          not null
#  target_user_id :integer         not null
#
# Indexes
#
#  idx_wimf_user_tags_proposer_target_label  (proposer_id,target_user_id,label) UNIQUE
#  idx_wimf_user_tags_target_status          (target_user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (proposer_id => users.id) ON DELETE => cascade
#  fk_rails_...  (target_user_id => users.id) ON DELETE => cascade
#
