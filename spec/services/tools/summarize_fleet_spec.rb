require "rails_helper"

RSpec.describe Tools::SummarizeFleet do
  before do
    travel_to Time.zone.parse("2026-11-05 10:00")
    dc = create(:location, name: "Data-Center-1")
    create(:asset, category: "server", location: dc, purchased_on: Date.new(2023, 1, 1), warranty_until: Date.new(2026, 1, 1))
    create(:asset, category: "server", location: dc, purchased_on: Date.new(2023, 1, 1), warranty_until: Date.new(2026, 12, 1))
    laptop = create(:asset, category: "laptop", status: "checked_out")
    create(:checkout, asset: laptop, out_at: 20.days.ago, due_at: 6.days.ago)
    create(:maintenance_task, asset: laptop, due_on: Date.new(2026, 10, 1))
    create(:service, criticality: "critical")
  end

  it "aggregates the whole fleet" do
    data = expect_ok(described_class.call({}))
    expect(data).to include("total_assets" => 3, "as_of" => "2026-11-05")
    expect(data["by_status"]).to eq("available" => 2, "checked_out" => 1)
    expect(data["by_category"]).to eq("server" => 2, "laptop" => 1)
    expect(data["warranty"]).to eq("expired" => 1, "expiring_within_90_days" => 1)
    expect(data["checkouts"]).to eq("open" => 1, "overdue" => 1)
    expect(data["maintenance"]).to include("scheduled" => 1, "overdue" => 1)
    expect(data["services_by_criticality"]).to eq("critical" => 1)
  end

  it "scopes to a location" do
    data = expect_ok(described_class.call(location: "data-center"))
    expect(data).to include("total_assets" => 2, "scope" => "data-center")
    expect(data).not_to have_key("services_by_criticality")
    expect_error(described_class.call(location: "Mars"), "not_found")
  end
end
