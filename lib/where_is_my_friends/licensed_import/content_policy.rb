# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class ContentPolicy
      RULES = {
        "minor_or_age_unknown" => [
          /\b(?:i am|i'm|aged?)\s+(?:[0-9]|1[0-7])\b/i,
          /\b(?:minor|underage|high schooler?|middle schooler?|teenager)\b/i
        ],
        "nonconsensual" => [
          /\b(?:forced|coerced|without (?:my|their) consent|said no|non-?consensual|assaulted)\b/i
        ],
        "explicit_sexual" => [
          /\b(?:porn(?:ographic)?|intercourse|explicit sex|sexual services?|genitals?)\b/i
        ],
        "self_harm" => [
          /\b(?:suicide|kill myself|self[- ]harm|cut myself|eating disorder)\b/i
        ],
        "medical_advice" => [
          /\b(?:medical advice|diagnos(?:e|is)|prescription|dosage|medication|treatment plan)\b/i
        ],
        "legal_advice" => [
          /\b(?:legal advice|lawyer|attorney|criminal liability|lawsuit|sue (?:them|him|her)|in court)\b/i
        ],
        "illegal_activity" => [
          /\b(?:shoplift|steal|fraud|hack(?:ing)?|without getting caught|evade police|illegal drugs?)\b/i
        ]
      }.freeze

      def failure_code(text)
        normalized = text.to_s
        RULES.each do |code, patterns|
          return code if patterns.any? { |pattern| normalized.match?(pattern) }
        end
        nil
      end
    end
  end
end
