# frozen_string_literal: true

module WhereIsMyFriends
  class ViewerAwareMemberSelection
    DEFAULT_SCAN_MULTIPLIER = 3
    Result = Struct.new(:items, :limited, keyword_init: true)

    def self.eligible_users(scope = User.all)
      scope.activated.not_staged.not_suspended.not_silenced
    end

    def initialize(viewer:, guardian: nil)
      @guardian = guardian || viewer.guardian
    end

    def account_eligible?(member)
      member.active? && !member.staged? && !member.suspended? &&
        !member.silenced?
    end

    def visible?(member)
      account_eligible?(member) && @guardian.can_see_profile?(member)
    end

    def select(scope:, limit:, scan_limit: limit, &member_for)
      member_for ||= ->(item) { item }
      selected = []
      offset = 0
      limited = false

      while offset < scan_limit
        batch_limit = [limit, scan_limit - offset].min
        batch = scope.offset(offset).limit(batch_limit).to_a
        break if batch.empty?

        selected.concat(batch.select { |item| visible?(member_for.call(item)) })
        break if selected.length >= limit || batch.length < batch_limit

        offset += batch.length
        if offset >= scan_limit
          limited = scope.offset(offset).exists?
          break
        end
      end

      Result.new(items: selected.first(limit), limited: limited)
    end
  end
end
