require "rails_helper"

RSpec.describe Tools::SearchAssets do
  let!(:dc) { create(:location, name: "Data-Center-1") }
  let!(:hq) { create(:location, name: "HQ") }
  let!(:ann) { create(:person, name: "Ann Lee", email: "ann@example.test") }
  let!(:old_server) { create(:asset, tag: "S-1", name: "DB-Server", category: "server", location: dc, warranty_until: Date.new(2026, 1, 1), purchased_on: Date.new(2023, 1, 1)) }
  let!(:new_server) { create(:asset, tag: "S-2", name: "App-Server", category: "server", location: dc, warranty_until: Date.new(2026, 12, 1), purchased_on: Date.new(2024, 1, 1)) }
  let!(:laptop) { create(:asset, tag: "L-1", name: "ThinkPad", category: "laptop", status: "checked_out", location: hq, custodian: ann) }

  before { travel_to Time.zone.parse("2026-11-05 10:00") }

  it "filters by location and expired warranty" do
    data = expect_ok(described_class.call(location: "data-center", warranty: "expired"))
    expect(data["assets"].map { |a| a["tag"] }).to eq(["S-1"])
    expect(data["assets"].first).to include("warranty_expired" => true, "location" => "Data-Center-1")
  end

  it "combines free text with category and custodian filters" do
    expect(expect_ok(described_class.call(query: "server", category: "server"))["total"]).to eq(2)
    expect(expect_ok(described_class.call(custodian: "ann@"))["assets"].map { |a| a["tag"] }).to eq(["L-1"])
  end

  it "finds warranties expiring within N days" do
    expect(expect_ok(described_class.call(warranty_expires_within_days: 30))["assets"].map { |a| a["tag"] }).to eq(["S-2"])
  end

  it "lists overdue checkouts with who has them, oldest due first" do
    create(:checkout, asset: laptop, person: ann, out_at: 20.days.ago, due_at: 6.days.ago)
    other = create(:asset, tag: "L-2", category: "laptop", status: "checked_out")
    create(:checkout, asset: other, person: ann, out_at: 30.days.ago, due_at: 10.days.ago)
    data = expect_ok(described_class.call(category: "laptop", overdue: true))
    expect(data["assets"].map { |a| a["tag"] }).to eq(%w[L-2 L-1])
    expect(data["assets"].first["checkout"]).to include("person" => "Ann Lee", "overdue" => true, "days_overdue" => 10)
  end

  it "caps and reports truncation" do
    data = expect_ok(described_class.call(limit: 1))
    expect(data).to include("total" => 3, "returned" => 1, "truncated" => true)
    expect_error(described_class.call(limit: 51), "invalid_input")
    expect_error(described_class.call(category: "spaceship"), "invalid_input")
  end
end
