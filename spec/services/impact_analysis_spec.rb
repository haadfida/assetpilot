require "rails_helper"

RSpec.describe ImpactAnalysis do
  # Graph (source -> target means "source depends on target"):
  #   svc_a -> svc_b -> srv -> net        (chain)
  #   svc_b -> svc_a                      (cycle between services)
  #   svc_c -> srv ; laptop -> svc_c
  #   net -> laptop                       (cycle back to the root)
  let!(:owner_a) { create(:person) }
  let!(:owner_c) { create(:person) }
  let!(:keeper) { create(:person) }
  let!(:net) { create(:asset, category: "network", name: "net") }
  let!(:srv) { create(:asset, category: "server", name: "srv") }
  let!(:laptop) { create(:asset, name: "laptop", custodian: keeper) }
  let!(:svc_a) { create(:service, owner: owner_a) }
  let!(:svc_b) { create(:service) }
  let!(:svc_c) { create(:service, owner: owner_c) }

  before do
    create(:dependency, source: srv, target: net)
    create(:dependency, source: svc_b, target: srv, kind: "runs_on")
    create(:dependency, source: svc_a, target: svc_b)
    create(:dependency, source: svc_b, target: svc_a) # cycle
    create(:dependency, source: svc_c, target: srv, kind: "runs_on")
    create(:dependency, source: laptop, target: svc_c)
    create(:dependency, source: net, target: laptop) # cycle back to the root
  end

  it "finds transitive dependents with depths, terminating on cycles and excluding the root" do
    r = described_class.call(type: "Asset", id: net.id)
    expect(r.assets.map { |a, d| [a.name, d] }).to contain_exactly(["srv", 1], ["laptop", 3])
    expect(r.services.map { |s, d| [s.id, d] }).to contain_exactly([svc_b.id, 2], [svc_c.id, 2], [svc_a.id, 3])
    expect(r.assets.map(&:first)).not_to include(net)
  end

  it "returns affected people (service owners and asset custodians)" do
    r = described_class.call(type: "Asset", id: net.id)
    expect(r.people).to contain_exactly(owner_a, owner_c, keeper)
  end

  it "respects the depth limit" do
    r = described_class.call(type: "Asset", id: net.id, max_depth: 2)
    expect(r.services.map(&:first)).to contain_exactly(svc_b, svc_c)
    expect(r.assets.map(&:first)).to contain_exactly(srv)
  end

  it "handles a pure two-node cycle" do
    r = described_class.call(type: "Service", id: svc_a.id)
    expect(r.services.map(&:first)).to eq([svc_b])
  end

  it "returns nothing for a node nobody depends on" do
    lonely = create(:asset)
    r = described_class.call(type: "Asset", id: lonely.id)
    expect([r.services, r.assets, r.people]).to all(be_empty)
  end

  it "raises NotFound for unknown nodes or types" do
    expect { described_class.call(type: "Asset", id: 0) }.to raise_error(ImpactAnalysis::NotFound)
    expect { described_class.call(type: "Person", id: 1) }.to raise_error(ImpactAnalysis::NotFound)
  end
end
