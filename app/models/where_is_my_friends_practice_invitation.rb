# frozen_string_literal: true

class WhereIsMyFriendsPracticeInvitation < ActiveRecord::Base
  STATUSES = %w[pending accepted declined ignored cancelled].freeze
  SOURCES = %w[native legacy_reconfirmed].freeze
  MAX_NOTE_LENGTH = 500

  belongs_to :sender, class_name: "User"
  belongs_to :recipient, class_name: "User"
  belongs_to :tag, optional: true
  belongs_to :pm_topic, class_name: "Topic", optional: true

  before_validation :snapshot_interest_name

  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :interest_name, presence: true, length: { maximum: 255 }
  validates :note, length: { maximum: MAX_NOTE_LENGTH }, allow_blank: true
  validate :participants_must_be_distinct

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def pending?
    status == "pending"
  end

  def preset_message(locale:)
    I18n.t(
      "where_is_my_friends.practice_invitations.preset_message",
      username: recipient.username,
      interest: interest_name,
      locale: locale
    )
  end

  def response_message(locale:)
    lines = [
      I18n.t(
        "where_is_my_friends.practice_invitations.accepted_message",
        username: sender.username,
        interest: interest_name,
        locale: locale
      )
    ]
    if proposed_at
      lines << I18n.t(
        "where_is_my_friends.practice_invitations.proposed_time",
        time: I18n.l(proposed_at, format: :long, locale: locale),
        locale: locale
      )
    end
    if note.present?
      lines << I18n.t(
        "where_is_my_friends.practice_invitations.original_note",
        note: note,
        locale: locale
      )
    end
    lines.join("\n\n")
  end

  private

  def snapshot_interest_name
    self.interest_name = tag.name if interest_name.blank? && tag
  end

  def participants_must_be_distinct
    if sender_id.present? && sender_id == recipient_id
      errors.add(:recipient_id, :invalid)
    end
  end
end
