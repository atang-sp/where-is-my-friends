# frozen_string_literal: true

module WhereIsMyFriends
  class AiProviderProfilesController < ::Admin::AdminController
    requires_plugin "where-is-my-friends"

    before_action :find_profile, only: %i[update destroy test activate]

    def index
      render json: {
               licensed_import_enabled: SiteSetting.licensed_import_enabled,
               profiles:
                 WhereIsMyFriendsAiProviderProfile
                   .order(:purpose, :name, :id)
                   .map { |profile| serialize(profile) }
             }
    end

    def create
      profile = WhereIsMyFriendsAiProviderProfile.new(profile_params)
      profile.created_by_id = current_user.id
      profile.updated_by_id = current_user.id
      if profile.save
        log_profile_action("create", profile, api_key_configured: true)
        render json: serialize(profile), status: :created
      else
        render_validation_errors(profile)
      end
    end

    def update
      attributes = profile_params
      attributes.delete(:api_key) if attributes[:api_key].blank?
      api_key_updated = attributes.key?(:api_key)
      @profile.updated_by_id = current_user.id
      if @profile.update(attributes)
        log_profile_action("update", @profile, api_key_updated: api_key_updated)
        render json: serialize(@profile)
      else
        render_validation_errors(@profile)
      end
    end

    def destroy
      @profile.destroy!
      log_profile_action("delete", @profile)
      SiteSetting.licensed_import_enabled = false
      render json: { success: true }
    end

    def test
      result = LicensedImport::ProviderTester.new(profile: @profile).call
      log_profile_action(
        "test",
        @profile,
        success: result.success?,
        error_code: result.error_code
      )
      status = result.success? ? :ok : :unprocessable_entity
      render json: {
               success: result.success?,
               error_code: result.error_code,
               profile: serialize(@profile.reload)
             },
             status: status
    end

    def activate
      @profile.activate!
      log_profile_action("activate", @profile, active: true)
      render json: { success: true, profile: serialize(@profile) }
    rescue LicensedImport::AiGateway::Error
      render json: {
               success: false,
               error_code: "verification_required"
             },
             status: :unprocessable_entity
    end

    private

    def find_profile
      @profile = WhereIsMyFriendsAiProviderProfile.find(params[:id])
    end

    def profile_params
      params.require(:profile).permit(
        :name,
        :purpose,
        :protocol,
        :structured_output_mode,
        :base_url,
        :model,
        :api_key
      )
    end

    def serialize(profile)
      {
        id: profile.id,
        name: profile.name,
        purpose: profile.purpose,
        protocol: profile.protocol,
        structured_output_mode: profile.structured_output_mode,
        base_url: profile.base_url,
        model: profile.model,
        api_key_configured: profile.api_key.present?,
        active: profile.active,
        verified: profile.verified_for_current_configuration?,
        verified_at: profile.verified_at,
        last_tested_at: profile.last_tested_at,
        last_test_status: profile.last_test_status,
        last_test_error_code: profile.last_test_error_code,
        updated_at: profile.updated_at
      }
    end

    def render_validation_errors(profile)
      render json: {
               success: false,
               errors: profile.errors.full_messages
             },
             status: :unprocessable_entity
    end

    def log_profile_action(action, profile, details = {})
      StaffActionLogger.new(current_user).log_custom(
        "#{action}_where_is_my_friends_ai_provider_profile",
        {
          profile_id: profile.id,
          profile_name: profile.name,
          purpose: profile.purpose,
          subject: profile.name
        }.merge(details)
      )
    end
  end
end
