# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::InterestCatalogue do
  describe ".pair_score" do
    it "gives complementary score of 6 for active_role and passive_role" do
      expect(described_class.pair_score("主动", "被动")).to eq(6)
      expect(described_class.pair_score("被动", "主动")).to eq(6)
    end

    it "gives complementary score of 6 for active_role and brat_interaction" do
      expect(described_class.pair_score("主动", "Brat互动")).to eq(6)
      expect(described_class.pair_score("Brat互动", "主动")).to eq(6)
    end

    it "gives compatible score of 5 for switch_role with active, passive, and switch" do
      expect(described_class.pair_score("双向", "主动")).to eq(5)
      expect(described_class.pair_score("主动", "双向")).to eq(5)
      expect(described_class.pair_score("双向", "被动")).to eq(5)
      expect(described_class.pair_score("被动", "双向")).to eq(5)
      expect(described_class.pair_score("双向", "双向")).to eq(5)
    end

    it "deprioritizes identical active or passive roles for practice matchmaking" do
      expect(described_class.pair_score("主动", "主动")).to eq(1)
      expect(described_class.pair_score("被动", "被动")).to eq(1)
    end

    it "preserves standard identical score of 6 for non-role interests" do
      expect(described_class.pair_score("戒尺", "戒尺")).to eq(6)
      expect(described_class.pair_score("师生场景", "师生场景")).to eq(6)
      expect(described_class.pair_score("事后复盘", "事后复盘")).to eq(6)
    end

    it "preserves related score of 2 for related non-role interests" do
      expect(described_class.pair_score("戒尺", "轻板")).to eq(2)
    end
  end

  describe ".match" do
    it "ranks complementary role higher than identical role" do
      active_match =
        described_class.match(
          viewer_names: ["主动", "戒尺"],
          candidate_names: ["被动", "戒尺"]
        )
      identical_match =
        described_class.match(
          viewer_names: ["主动", "戒尺"],
          candidate_names: ["主动", "戒尺"]
        )

      expect(active_match.score).to eq(12)
      expect(identical_match.score).to eq(7)
      expect(active_match.score).to be > identical_match.score
      expect(active_match.reason_names).to include("主动", "戒尺")
    end
  end
end
