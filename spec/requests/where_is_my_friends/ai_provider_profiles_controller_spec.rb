# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::AiProviderProfilesController do
  fab!(:user)
  fab!(:admin)

  def create_profile
    WhereIsMyFriendsAiProviderProfile.create!(
      name: "Gateway",
      purpose: "generation",
      protocol: "responses",
      base_url: "https://api.openai.com/v1",
      model: "supplier-model",
      api_key: "never-return-this",
      created_by_id: admin.id,
      updated_by_id: admin.id
    )
  end

  it "allows only administrators and never serializes credentials" do
    profile = create_profile

    sign_in(user)
    get "/where-is-my-friends/admin/ai-provider-profiles.json"
    expect(response.status).to eq(404).or eq(403)

    sign_in(admin)
    get "/where-is-my-friends/admin/ai-provider-profiles.json"

    expect(response.status).to eq(200)
    serialized = response.parsed_body.fetch("profiles").sole
    expect(serialized).to include(
      "id" => profile.id,
      "name" => "Gateway",
      "api_key_configured" => true,
      "active" => false
    )
    expect(serialized.keys).not_to include("api_key")
    expect(response.body).not_to include("never-return-this")
  end

  it "creates and updates profiles while blank keys retain the secret" do
    sign_in(admin)
    post "/where-is-my-friends/admin/ai-provider-profiles.json",
         params: {
           profile: {
             name: "Compatible supplier",
             purpose: "moderation",
             protocol: "chat_completions",
             base_url: "https://api.openai.com/v1/",
             model: "vendor-model",
             api_key: "initial-secret"
           }
         }

    expect(response.status).to eq(201)
    profile = WhereIsMyFriendsAiProviderProfile.find(response.parsed_body["id"])
    saved_key = profile.api_key
    expect(profile.api_key).to eq("initial-secret")
    expect(profile.purpose).to eq("generation")

    put "/where-is-my-friends/admin/ai-provider-profiles/#{profile.id}.json",
        params: {
          profile: {
            name: "Renamed supplier",
            purpose: "moderation",
            protocol: "chat_completions",
            base_url: "https://api.openai.com/v1",
            model: "vendor-model",
            api_key: ""
          }
        }

    expect(response.status).to eq(200)
    expect(profile.reload.name).to eq("Renamed supplier")
    expect(profile.api_key).to eq(saved_key)
  end

  it "tests and activates only the verified current configuration" do
    profile = create_profile
    sign_in(admin)
    result =
      WhereIsMyFriends::LicensedImport::ProviderTester::Result.new(
        success: true,
        error_code: nil
      )
    tester =
      instance_double(
        WhereIsMyFriends::LicensedImport::ProviderTester,
        call: result
      )
    allow(WhereIsMyFriends::LicensedImport::ProviderTester).to receive(
      :new
    ).and_return(tester)

    post "/where-is-my-friends/admin/ai-provider-profiles/#{profile.id}/test.json"

    expect(response.status).to eq(200)

    profile.update_columns(
      verified_at: Time.zone.now,
      verified_config_digest: profile.configuration_digest,
      last_test_status: "passed"
    )
    post "/where-is-my-friends/admin/ai-provider-profiles/#{profile.id}/activate.json"

    expect(response.status).to eq(200)
    expect(profile.reload).to be_active
    expect(SiteSetting.licensed_import_enabled).to eq(false)
  end

  it "audits administrator actions without logging API key values" do
    sign_in(admin)
    post "/where-is-my-friends/admin/ai-provider-profiles.json",
         params: {
           profile: {
             name: "Audited gateway",
             purpose: "generation",
             protocol: "responses",
             base_url: "https://api.openai.com/v1",
             model: "audited-model",
             api_key: "audit-secret-never-log"
           }
         }
    profile = WhereIsMyFriendsAiProviderProfile.find(response.parsed_body["id"])

    put "/where-is-my-friends/admin/ai-provider-profiles/#{profile.id}.json",
        params: {
          profile: {
            name: profile.name,
            purpose: profile.purpose,
            protocol: profile.protocol,
            base_url: profile.base_url,
            model: profile.model,
            api_key: "replacement-secret-never-log"
          }
        }

    result =
      WhereIsMyFriends::LicensedImport::ProviderTester::Result.new(
        success: true,
        error_code: nil
      )
    allow(WhereIsMyFriends::LicensedImport::ProviderTester).to receive(
      :new
    ).and_return(
      instance_double(
        WhereIsMyFriends::LicensedImport::ProviderTester,
        call: result
      )
    )
    post "/where-is-my-friends/admin/ai-provider-profiles/#{profile.id}/test.json"

    profile.reload.update_columns(
      verified_at: Time.zone.now,
      verified_config_digest: profile.configuration_digest,
      last_test_status: "passed"
    )
    post "/where-is-my-friends/admin/ai-provider-profiles/#{profile.id}/activate.json"
    delete "/where-is-my-friends/admin/ai-provider-profiles/#{profile.id}.json"

    action_types = %w[
      create_where_is_my_friends_ai_provider_profile
      update_where_is_my_friends_ai_provider_profile
      test_where_is_my_friends_ai_provider_profile
      activate_where_is_my_friends_ai_provider_profile
      delete_where_is_my_friends_ai_provider_profile
    ]
    histories =
      UserHistory.where(
        acting_user_id: admin.id,
        action: UserHistory.actions[:custom_staff]
      ).where(custom_type: action_types)

    expect(histories.pluck(:custom_type)).to contain_exactly(*action_types)
    expect(histories.pluck(:subject).uniq).to eq(["Audited gateway"])
    audit_text = histories.pluck(:details).join("\n")
    expect(audit_text).to include("profile_id: #{profile.id}")
    expect(audit_text).to include("api_key_updated: true")
    expect(audit_text).not_to include(
      "audit-secret-never-log",
      "replacement-secret-never-log"
    )
    action_types.each do |action_type|
      key = "admin_js.admin.logs.staff_actions.actions.#{action_type}"
      expect(I18n.t(key, locale: :en)).not_to include("Translation missing")
      expect(I18n.t(key, locale: :zh_CN)).not_to include("Translation missing")
    end
  end
end
