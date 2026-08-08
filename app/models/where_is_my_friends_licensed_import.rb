# frozen_string_literal: true

class WhereIsMyFriendsLicensedImport < ActiveRecord::Base
  STATUSES = %w[processing failed preview published hidden superseded].freeze
  SOURCE_TYPES = %w[stack_exchange wikimedia spanking_art].freeze

  belongs_to :topic, optional: true

  validates :source_question_id, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
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

# == Schema Information
#
# Table name: where_is_my_friends_licensed_imports
#
#  id                  :bigint           not null, primary key
#  answer_author       :string
#  answer_license      :string
#  failure_code        :string
#  published_at        :datetime
#  question_author     :string
#  question_license    :string
#  scheduled_for_date  :date
#  source_answer_url   :string
#  source_question_url :string
#  source_revised_at   :datetime
#  source_type         :string           default("stack_exchange"), not null
#  status              :string           not null
#  theme               :string
#  token_count         :integer          default(0), not null
#  translated_body     :text
#  translated_title    :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  first_post_id       :bigint
#  source_answer_id    :bigint
#  source_question_id  :bigint           not null
#  topic_id            :bigint
#
# Indexes
#
#  idx_wimf_licensed_import_daily_active   (scheduled_for_date) UNIQUE WHERE ((status)::text = ANY ((ARRAY['processing'::character varying, 'preview'::character varying, 'published'::character varying])::text[]))
#  idx_wimf_licensed_import_source         (source_question_id,created_at)
#  idx_wimf_licensed_import_source_active  (source_type,source_question_id) UNIQUE WHERE ((status)::text = ANY ((ARRAY['processing'::character varying, 'preview'::character varying, 'published'::character varying])::text[]))
#  idx_wimf_licensed_import_status         (status,created_at)
#  idx_wimf_licensed_import_topic          (topic_id)
#
