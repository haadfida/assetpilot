require "rails_helper"

RSpec.describe Tools::ImpactAnalysis do
  let(:owner) { create(:person, name: "Olive Owner") }
  let(:holder) { create(:person, name: "Hal Holder") }
  let(:db) { create(:asset, tag: "S-1", name: "DB-Server", category: "server") }
  let(:billing) { create(:service, name: "Billing API", criticality: "critical", owner: owner) }
  let(:portal) { create(:service, name: "Customer Portal", criticality: "high") }
  let(:laptop) { create(:asset, tag: "L-1", category: "laptop", custodian: holder) }

  before do
    create(:dependency, source: billing, target: db, kind: "runs_on")
    create(:dependency, source: portal, target: billing)
    create(:dependency, source: laptop, target: portal)
    create(:dependency, source: db, target: portal) # cycle back to the root
  end

  it "resolves the node by name and summarises the M1 CTE result" do
    data = expect_ok(described_class.call(node_type: "asset", node: "db-server"))
    expect(data["root"]).to eq("type" => "asset", "name" => "DB-Server", "tag" => "S-1")
    expect(data["counts"]).to eq("services" => 2, "assets" => 1, "people" => 2)
    expect(data["services"].map { |s| [s["name"], s["depth"], s["owner"]] }).to eq([["Billing API", 1, "Olive Owner"], ["Customer Portal", 2, nil]])
    expect(data["services_by_criticality"]).to include("critical" => 1, "high" => 1)
    expect(data["assets"]).to eq([{ "tag" => "L-1", "name" => laptop.name, "category" => "laptop", "depth" => 3, "custodian" => "Hal Holder" }])
  end

  it "accepts services and respects max_depth" do
    data = expect_ok(described_class.call(node_type: "service", node: "Billing API", max_depth: 1))
    expect(data["counts"]).to include("services" => 1, "assets" => 0)
    expect_error(described_class.call(node_type: "service", node: "Billing API", max_depth: 99), "invalid_input")
    expect_error(described_class.call(node_type: "service", node: "Nope"), "not_found")
    expect_error(described_class.call(node_type: "router", node: "x"), "invalid_input")
  end
end
