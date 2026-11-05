require "rails_helper"

# The same check as `bin/rails replays:verify`: seed the (transactional) test database with SeedData,
# re-run every recorded tool call, require identical outputs, and rebuild each fixture from its scenario.
RSpec.describe "db/replays fixtures" do
  it "are reproducible against the seeded database" do
    expect(Replays::Builder.new.verify_all).to eq([])
  end

  it "leave the database untouched" do
    expect { Replays::Builder.new.verify_all }.not_to change { [Asset.count, MaintenanceTask.count, Checkout.count] }
  end
end
