# frozen_string_literal: true

require "digest"

class WhereIsMyFriendsAiProviderProfile < ActiveRecord::Base
  PURPOSES = %w[generation].freeze
  GENERATION_PROTOCOLS = %w[responses chat_completions].freeze
  STRUCTURED_OUTPUT_MODES = %w[json_schema json_object].freeze
  CONFIGURATION_COLUMNS = %w[
    purpose
    protocol
    structured_output_mode
    base_url
    model
    api_key
  ].freeze

  validates :name,
            :purpose,
            :protocol,
            :base_url,
            :model,
            :api_key,
            presence: true
  validates :purpose, inclusion: { in: PURPOSES }
  validates :api_key, length: { maximum: 10_000 }
  validates :protocol, inclusion: { in: GENERATION_PROTOCOLS }
  validates :structured_output_mode, inclusion: { in: STRUCTURED_OUTPUT_MODES }
  validate :safe_base_url_syntax

  before_validation :normalize_configuration
  before_save :invalidate_changed_configuration
  after_commit :disable_import_after_configuration_change, on: %i[create update]

  scope :active_for, ->(purpose) { where(purpose: purpose, active: true) }

  def api_key!
    api_key.presence ||
      raise(WhereIsMyFriends::LicensedImport::AiGateway::MissingApiKey)
  end

  def configuration_digest
    Digest::SHA256.hexdigest(
      CONFIGURATION_COLUMNS.map { |column| public_send(column).to_s }.join("\0")
    )
  end

  def verified_for_current_configuration?
    verified_at.present? && verified_config_digest.present? &&
      ActiveSupport::SecurityUtils.secure_compare(
        verified_config_digest,
        configuration_digest
      )
  end

  def activate!
    self.class.transaction do
      with_lock do
        unless verified_for_current_configuration?
          raise WhereIsMyFriends::LicensedImport::AiGateway::InvalidResponse
        end

        api_key!
        self
          .class
          .where(purpose: purpose, active: true)
          .where.not(id: id)
          .update_all(active: false, updated_at: Time.zone.now)
        update_columns(active: true, updated_at: Time.zone.now)
      end
    end
    SiteSetting.licensed_import_enabled = false
    reload
  end

  def self.active_profile!(purpose)
    active_for(purpose).first ||
      raise(WhereIsMyFriends::LicensedImport::AiGateway::MissingApiKey)
  end

  private

  def normalize_configuration
    self.name = name.to_s.strip
    self.purpose = purpose.to_s.strip
    self.protocol = protocol.to_s.strip
    self.structured_output_mode =
      structured_output_mode.to_s.strip.presence || "json_schema"
    self.base_url = base_url.to_s.strip.sub(%r{/+\z}, "")
    self.model = model.to_s.strip

    self.structured_output_mode = "json_schema" if protocol == "responses"
  end

  def invalidate_changed_configuration
    return unless configuration_changed_before_save?

    self.active = false
    self.verified_at = nil
    self.verified_config_digest = nil
  end

  def disable_import_after_configuration_change
    return unless previous_changes.keys.intersect?(CONFIGURATION_COLUMNS)

    SiteSetting.licensed_import_enabled = false
  end

  def configuration_changed_before_save?
    CONFIGURATION_COLUMNS.any? do |column|
      will_save_change_to_attribute?(column)
    end
  end

  def safe_base_url_syntax
    if WhereIsMyFriends::LicensedImport::EndpointPolicy.safe_url_syntax?(
         base_url
       )
      return
    end

    errors.add(:base_url, :invalid)
  end
end

# == Schema Information
#
# Table name: where_is_my_friends_ai_provider_profiles
#
#  id                     :bigint           not null, primary key
#  active                 :boolean          default(FALSE), not null
#  api_key                :string(10000)    not null
#  base_url               :string           not null
#  last_test_error_code   :string
#  last_test_status       :string
#  last_tested_at         :datetime
#  model                  :string           not null
#  name                   :string           not null
#  protocol               :string           not null
#  purpose                :string           not null
#  structured_output_mode :string           default("json_schema"), not null
#  verified_at            :datetime
#  verified_config_digest :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  created_by_id          :bigint           not null
#  updated_by_id          :bigint           not null
#
# Indexes
#
#  idx_on_created_by_id_458394d3de              (created_by_id)
#  idx_on_updated_by_id_ecefe100b4              (updated_by_id)
#  idx_wimf_ai_profiles_one_active_per_purpose  (purpose) UNIQUE WHERE (active = true)
#
