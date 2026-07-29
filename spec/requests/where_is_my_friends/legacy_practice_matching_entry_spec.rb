# frozen_string_literal: true

RSpec.describe "Legacy practice matching entry" do
  if Discourse.plugins_by_name["discourse-plugin-matching"]
    it "keeps the read-only overlap page while the legacy plugin is installed" do
      get "/practice-matching"

      expect(response.status).to eq(200)
      expect(response).not_to be_redirect
    end
  else
    it "redirects to interest recommendations after the legacy plugin is removed" do
      get "/practice-matching"

      expect(response).to redirect_to("/where-is-my-friends/interests")
    end
  end
end
