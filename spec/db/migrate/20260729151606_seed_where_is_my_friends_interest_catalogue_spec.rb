# frozen_string_literal: true

require Rails.root.join(
          "plugins/where-is-my-friends/db/migrate/20260729151606_seed_where_is_my_friends_interest_catalogue.rb"
        )

RSpec.describe SeedWhereIsMyFriendsInterestCatalogue do
  before do
    @original_verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    Tag.where(name: "纯实践").delete_all
  end

  after { ActiveRecord::Migration.verbose = @original_verbose }

  it "adds the curated tags when upgrading an existing site" do
    allow(Migration::Helpers).to receive(:existing_site?).and_return(true)

    described_class.new.up

    expect(Tag.exists?(name: "纯实践")).to eq(true)
  end

  it "leaves fresh-install rows to the plugin fixture" do
    allow(Migration::Helpers).to receive(:existing_site?).and_return(false)

    described_class.new.up

    expect(Tag.exists?(name: "纯实践")).to eq(false)
  end
end
