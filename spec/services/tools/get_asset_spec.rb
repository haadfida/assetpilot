require "rails_helper"

RSpec.describe Tools::GetAsset do
  let(:switch) { create(:asset, tag: "N-1", name: "Core-Switch", category: "network") }
  let(:server) { create(:asset, tag: "S-1", name: "DB-Server", category: "server") }
  let(:svc) { create(:service, name: "Billing API") }

  before do
    create(:dependency, source: server, target: switch)
    create(:dependency, source: svc, target: server, kind: "runs_on")
    create(:maintenance_task, asset: server, kind: "repair", due_on: Date.new(2026, 12, 1))
  end

  it "resolves by tag, id or name and returns dependencies, dependents and maintenance" do
    [server.tag.downcase, server.id.to_s, "db-server"].each do |ref|
      data = expect_ok(described_class.call(asset: ref))
      expect(data["tag"]).to eq("S-1")
    end
    data = expect_ok(described_class.call(asset: "S-1"))
    expect(data["depends_on"]).to eq([{ "type" => "asset", "kind" => "depends_on", "name" => "Core-Switch", "tag" => "N-1" }])
    expect(data["direct_dependents"]).to eq("count" => 1, "services" => 1, "assets" => 0)
    expect(data["maintenance_tasks"].map { |t| t["kind"] }).to eq(["repair"])
    expect(data["checkout"]).to be_nil
  end

  it "returns not_found and ambiguous as structured errors" do
    expect_error(described_class.call(asset: "nope"), "not_found")
    create(:asset, name: "Twin"); create(:asset, name: "Twin")
    err = expect_error(described_class.call(asset: "twin"), "ambiguous")
    expect(err.dig("details", "candidates").size).to eq(2)
  end
end
