# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class TokenBudget
      class Exhausted < StandardError
      end

      def ensure_available!(maximum_tokens)
        if used_tokens + maximum_tokens.to_i >
             SiteSetting.licensed_import_monthly_token_budget.to_i
          raise Exhausted
        end
      end

      private

      def used_tokens
        WhereIsMyFriendsLicensedImport.where(
          created_at: Time.zone.now.beginning_of_month..
        ).sum(:token_count)
      end
    end
  end
end
