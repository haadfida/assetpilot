require "rails_helper"

RSpec.describe Tools::CheckinAsset do
  let!(:asset) { create(:asset, tag: "L-1", category: "laptop", status: "checked_out") }
  let!(:ann) { create(:person, name: "Ann Lee") }

  before { travel_to Time.zone.parse("2026-11-05 10:00") }

  it "closes the open checkout, frees the asset and reports lateness" do
    co = create(:checkout, asset: asset, person: ann, out_at: Time.zone.parse("2026-10-01 09:00"), due_at: Time.zone.parse("2026-10-15 09:00"))
    data = expect_ok(described_class.call(asset: "l-1"))
    expect(data).to include("checkout_id" => co.id, "returned_late" => true, "days_overdue" => 21,
                            "checked_in_at" => "2026-11-05T10:00:00Z")
    expect(co.reload.in_at).to be_present
    expect(asset.reload.status).to eq("available")
  end

  it "errors when there is no open checkout" do
    asset.update!(status: "available")
    expect_error(described_class.call(asset: "L-1"), "not_checked_out")
    expect_error(described_class.call(asset: "L-404"), "not_found")
  end
end
