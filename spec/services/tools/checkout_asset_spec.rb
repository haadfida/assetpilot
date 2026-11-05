require "rails_helper"

RSpec.describe Tools::CheckoutAsset do
  let!(:asset) { create(:asset, tag: "L-1", category: "laptop") }
  let!(:ann) { create(:person, name: "Ann Lee", email: "ann@example.test") }

  before { travel_to Time.zone.parse("2026-11-05 10:00") }

  it "checks the asset out and marks it checked_out" do
    data = expect_ok(described_class.call(asset: "L-1", person: "ann@example.test", due_on: "2026-11-19"))
    expect(data).to include("due_at" => "2026-11-19T17:00:00Z")
    expect(data.dig("person", "name")).to eq("Ann Lee")
    expect(asset.reload.status).to eq("checked_out")
    expect(Checkout.open.where(asset: asset).count).to eq(1)
  end

  it "refuses an asset that is already out, naming the holder, without changing anything" do
    create(:checkout, asset: asset, person: ann, out_at: 2.days.ago, due_at: 5.days.from_now)
    err = expect_error(described_class.call(asset: "L-1", person: "Ann Lee", due_on: "2026-11-19"), "already_checked_out")
    expect(err.dig("details", "checkout", "person")).to eq("Ann Lee")
    expect(Checkout.count).to eq(1)
  end

  it "validates due dates, retired assets and people" do
    expect_error(described_class.call(asset: "L-1", person: "ann@example.test", due_on: "2026-11-05"), "invalid_due_date")
    expect_error(described_class.call(asset: "L-1", person: "ann@example.test", due_on: "2027-12-01"), "invalid_due_date")
    expect_error(described_class.call(asset: "L-1", person: "ann@example.test", due_on: "next week"), "invalid_input")
    expect_error(described_class.call(asset: "L-1", person: "nobody", due_on: "2026-11-19"), "not_found")
    asset.update!(status: "retired")
    expect_error(described_class.call(asset: "L-1", person: "ann@example.test", due_on: "2026-11-19"), "asset_unavailable")
    expect(Checkout.count).to eq(0)
  end

  it "requires every field" do
    expect_error(described_class.call(asset: "L-1"), "invalid_input")
  end
end
