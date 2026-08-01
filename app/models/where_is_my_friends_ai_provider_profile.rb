# frozen_string_literal: true

require "digest"

class WhereIsMyFriendsAiProviderProfile < ActiveRecord::Base
  PURPOSES = %w[generation moderation].freeze
  GENERATION_PROTOCOLS = %w[responses chat_completions].freeze
  MODERATION_PROTOCOL = "openai_moderation"
  MODERATION_BASE_URL = "https://api.openai.com/v1"
  MODERATION_MODEL = "omni-moderation-latest"
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
  validates :protocol,
            inclusion: {
              in: GENERATION_PROTOCOLS + [MODERATION_PROTOCOL]
            }
  validates :structured_output_mode, inclusion: { in: STRUCTURED_OUTPUT_MODES }
  validate :valid_protocol_for_purpose
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

    if purpose == "moderation"
      self.protocol = MODERATION_PROTOCOL
      self.base_url = MODERATION_BASE_URL
      self.model = MODERATION_MODEL
      self.structured_output_mode = "json_schema"
    elsif protocol == "responses"
      self.structured_output_mode = "json_schema"
    end
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

  def valid_protocol_for_purpose
    allowed =
      if purpose == "generation"
        GENERATION_PROTOCOLS
      elsif purpose == "moderation"
        [MODERATION_PROTOCOL]
      else
        []
      end
    errors.add(:protocol, :inclusion) if allowed.exclude?(protocol)
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
