# frozen_string_literal: true

class WhereIsMyFriendsLicensedImport < ActiveRecord::Base
  STATUSES = %w[processing failed preview published hidden superseded].freeze

  belongs_to :topic, optional: true

  validates :source_question_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :successful, -> { where(status: %w[preview published]) }
  scope :published, -> { where(status: "published") }

  def add_tokens!(count)
    increment!(:token_count, count.to_i) if count.to_i.positive?
  end

  def fail!(code)
    update!(
      status: "failed",
      failure_code: code,
      translated_title: nil,
      translated_body: nil
    )
    self
  end
end
