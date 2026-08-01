# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::ContentPolicy do
  subject(:policy) { described_class.new }

  it "rejects every prohibited hard-risk family before model review" do
    examples = {
      "minor_or_age_unknown" =>
        "A child is 16 and needs advice about meeting this adult.",
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
    expect(
      policy.failure_code(
        "I am an adult, but I don't know the age of the person I met online."
      )
    ).to eq("minor_or_age_unknown")
    expect(policy.failure_code("I am an adult and need a boundary.")).to be_nil
    expect(
      policy.failure_code(
        "Adults may discuss intercourse without giving explicit details."
      )
    ).to be_nil
    expect(
      policy.failure_code(
        "Adults may choose a consequence for a minor mistake."
      )
    ).to be_nil
    expect(
      policy.failure_code("An adult describes a minor participant.")
    ).to eq("minor_or_age_unknown")
  end

  it "accepts curated adult-only reference material without weakening minor rules" do
    reference =
      "Consensual spanking partners should agree on boundaries and aftercare."

    expect(policy.failure_code(reference, adult_confirmed: true)).to be_nil
    expect(
      policy.failure_code(
        "A 16-year-old asks about spanking.",
        adult_confirmed: true
      )
    ).to eq("minor_or_age_unknown")
    expect(policy.failure_code(reference)).to eq("minor_or_age_unknown")
  end
end
