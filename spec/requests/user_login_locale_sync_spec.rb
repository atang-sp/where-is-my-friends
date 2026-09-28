# frozen_string_literal: true

RSpec.describe "User login locale sync" do
  fab!(:user) do
    Fabricate(:user, locale: "zh_CN").tap do |u|
      u.password = "myawesomepassword"
      u.save!
      email_token = Fabricate(:email_token, user: u)
      EmailToken.confirm(email_token.token)
    end
  end

  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.allow_user_locale = true
    SiteSetting.set_locale_from_cookie = true
    SiteSetting.set_locale_from_param = true
  end

  describe "POST /session" do
    it "synchronizes user locale from locale cookie on successful login" do
      cookies["locale"] = "en"

      post "/session.json",
           params: {
             login: user.username,
             password: "myawesomepassword",
           }

      expect(response.status).to eq(200)
      expect(user.reload.locale).to eq("en")
    end

    it "synchronizes user locale from URL or body parameter when cookie is absent" do
      post "/session.json",
           params: {
             login: user.username,
             password: "myawesomepassword",
             tl: "ja",
           }

      expect(response.status).to eq(200)
      expect(user.reload.locale).to eq("ja")
    end

    it "does not update user locale if selected locale is unavailable" do
      cookies["locale"] = "invalid_lang"

      post "/session.json",
           params: {
             login: user.username,
             password: "myawesomepassword",
           }

      expect(response.status).to eq(200)
      expect(user.reload.locale).to eq("zh_CN")
    end

    it "does not update user locale when allow_user_locale setting is disabled" do
      SiteSetting.allow_user_locale = false
      cookies["locale"] = "en"

      post "/session.json",
           params: {
             login: user.username,
             password: "myawesomepassword",
           }

      expect(response.status).to eq(200)
      expect(user.reload.locale).to eq("zh_CN")
    end
  end
end
