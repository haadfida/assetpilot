require "rails_helper"

RSpec.describe Tools::ScheduleMaintenance do
  let!(:a) { create(:asset, tag: "S-1") }
  let!(:b) { create(:asset, tag: "S-2") }
  let!(:retired) { create(:asset, tag: "S-3", status: "retired") }

  before { travel_to Time.zone.parse("2026-11-05 10:00") }

  it "schedules one task per asset and skips retired and duplicate ones" do
    create(:maintenance_task, asset: b, kind: "inspection", due_on: Date.new(2026, 11, 12))
    data = expect_ok(described_class.call(assets: %w[S-1 S-2 S-3 s-1], kind: "inspection", due_on: "2026-11-12"))
    expect(data["scheduled"].map { |t| t["tag"] }).to eq(["S-1"])
    expect(data["skipped"]).to contain_exactly({ "tag" => "S-2", "reason" => "already_scheduled" }, { "tag" => "S-3", "reason" => "retired" })
    expect(a.maintenance_tasks.pluck(:kind, :status)).to eq([%w[inspection scheduled]])
  end

  it "is all-or-nothing when an asset cannot be resolved" do
    err = expect_error(described_class.call(assets: %w[S-1 NOPE], kind: "repair", due_on: "2026-11-12"), "not_found")
    expect(err.dig("details", "unresolved").map { |u| u["ref"] }).to eq(["NOPE"])
    expect(MaintenanceTask.count).to eq(0)
  end

  it "validates kind, dates and list size" do
    expect_error(described_class.call(assets: ["S-1"], kind: "exorcism", due_on: "2026-11-12"), "invalid_input")
    expect_error(described_class.call(assets: ["S-1"], kind: "repair", due_on: "2026-11-01"), "invalid_due_date")
    expect_error(described_class.call(assets: [], kind: "repair", due_on: "2026-11-12"), "invalid_input")
    expect_error(described_class.call(assets: Array.new(51) { |i| "X-#{i}" }, kind: "repair", due_on: "2026-11-12"), "invalid_input")
  end
end
