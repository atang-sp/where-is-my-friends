# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::FlyingChessClaimsController do
  fab!(:user)
  fab!(:profile) do
    Fabricate(
      :where_is_my_friends_flying_chess_profile,
      user: user,
      completed_games: 1,
      first_completed_at: 1.day.ago,
      profile_visible: false
    )
  end

  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_flying_chess_achievements_enabled = false
  end

  it "requires login for both write endpoints" do
    put "/where-is-my-friends/flying-chess/profile.json",
        params: {
          profile_visible: true
        }
    expect(response.status).to eq(403)

    post "/where-is-my-friends/flying-chess/claims.json",
         params: {
           claim_token: "signed-token"
         }
    expect(response.status).to eq(403)
  end

  context "when signed in" do
    before { sign_in(user) }

    it "does not update profile visibility while achievements are disabled" do
      expect do
        put "/where-is-my-friends/flying-chess/profile.json",
            params: {
              profile_visible: true
            }
      end.not_to change { profile.reload.profile_visible? }

      expect(response.status).to eq(404)
    end

    it "does not accept completion claims while achievements are disabled" do
      post "/where-is-my-friends/flying-chess/claims.json",
           params: {
             claim_token: "signed-token"
           }

      expect(response.status).to eq(404)
    end

    it "updates the owner's profile while achievements are enabled" do
      SiteSetting.where_is_my_friends_flying_chess_achievements_enabled = true

      expect do
        put "/where-is-my-friends/flying-chess/profile.json",
            params: {
              profile_visible: true
            }
      end.to change { profile.reload.profile_visible? }.from(false).to(true)

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("achievement")).to include(
        "profile_visible" => true,
        "can_manage" => true
      )
    end
  end
end
