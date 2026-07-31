# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::ContentPolicy do
  subject(:policy) { described_class.new }

  it "rejects every prohibited hard-risk family before model review" do
    examples = {
      "minor_or_age_unknown" =>
        "I am 16 and need advice about meeting this adult.",
      "nonconsensual" => "My date forced me after I said no.",
      "explicit_sexual" =>
        "This contains pornographic details about intercourse.",
      "self_harm" => "I want instructions to kill myself.",
      "medical_advice" =>
        "What prescription dosage should I take for this diagnosis?",
      "legal_advice" => "What legal advice avoids criminal liability in court?",
      "illegal_activity" => "How can I shoplift without getting caught?"
    }

    expect(
      examples.transform_values { |text| policy.failure_code(text) }
    ).to eq(examples.keys.index_with(&:itself))
  end

  it "fails closed when adulthood is unknown or an age is explicitly under 18" do
    expect(
      policy.failure_code("How can I set a boundary with a friend?")
    ).to eq("minor_or_age_unknown")
    expect(
      policy.failure_code("My 16-year-old friend needs a boundary.")
    ).to eq("minor_or_age_unknown")
    expect(policy.failure_code("I am an adult and need a boundary.")).to be_nil
  end
end
