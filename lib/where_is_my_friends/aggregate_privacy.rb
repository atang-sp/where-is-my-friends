# frozen_string_literal: true

module WhereIsMyFriends
  class AggregatePrivacy
    MIN_THRESHOLD = 2
    MAX_THRESHOLD = 20

    def self.protect_counts(attributes, *count_keys)
      count_keys.each_with_object(attributes.dup) do |key, protected|
        count = protected.fetch(key).to_i
        suppressed = suppressed?(count)
        protected[key] = nil if suppressed
        protected[:"#{key}_suppressed"] = suppressed
      end
    end

    def self.suppressed?(count)
      count.to_i < threshold
    end

    def self.threshold
      SiteSetting.where_is_my_friends_aggregate_privacy_threshold.to_i.clamp(
        MIN_THRESHOLD,
        MAX_THRESHOLD
      )
    end
  end
end
