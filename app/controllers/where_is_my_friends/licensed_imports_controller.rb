# frozen_string_literal: true

module WhereIsMyFriends
  class LicensedImportsController < ::ApplicationController
    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in
    before_action :ensure_admin

    def index
      render json: {
               enabled: SiteSetting.licensed_import_enabled,
               dry_run: SiteSetting.licensed_import_dry_run,
               generation_provider: active_generation_provider,
               moderation_provider: active_moderation_provider,
               interval_hours: SiteSetting.licensed_import_interval_hours,
               publish_hour_beijing: SiteSetting.licensed_import_publish_hour,
               monthly_token_budget:
                 SiteSetting.licensed_import_monthly_token_budget,
               monthly_tokens_used: monthly_tokens_used,
               engagement:
                 WhereIsMyFriends::LicensedImport::EngagementGuard.new.stats,
               previews: previews,
               recent_failures: recent_failures
             }
    end

    private

    def active_generation_provider
      active_provider("generation")
    end

    def active_moderation_provider
      active_provider("moderation")
    end

    def active_provider(purpose)
      profile = WhereIsMyFriendsAiProviderProfile.active_for(purpose).first
      return if profile.blank?

      {
        id: profile.id,
        name: profile.name,
        protocol: profile.protocol,
        model: profile.model
      }
    end

    def previews
      WhereIsMyFriendsLicensedImport
        .where(status: "preview")
        .order(created_at: :desc)
        .limit(30)
        .map do |record|
          {
            id: record.id,
            source_question_id: record.source_question_id,
            source_question_url: record.source_question_url,
            source_answer_url: record.source_answer_url,
            question_author: record.question_author,
            answer_author: record.answer_author,
            question_license: record.question_license,
            answer_license: record.answer_license,
            theme: record.theme,
            translated_title: record.translated_title,
            translated_body: record.translated_body,
            token_count: record.token_count,
            created_at: record.created_at
          }
        end
    end

    def recent_failures
      WhereIsMyFriendsLicensedImport
        .where(status: "failed")
        .order(created_at: :desc)
        .limit(50)
        .pluck(:source_question_id, :failure_code, :token_count, :created_at)
        .map do |source_question_id, failure_code, token_count, created_at|
          {
            source_question_id: source_question_id,
            failure_code: failure_code,
            token_count: token_count,
            created_at: created_at
          }
        end
    end

    def monthly_tokens_used
      WhereIsMyFriendsLicensedImport.where(
        created_at: Time.zone.now.beginning_of_month..
      ).sum(:token_count)
    end

    def ensure_admin
      raise Discourse::InvalidAccess unless current_user.admin?
    end
  end
end
