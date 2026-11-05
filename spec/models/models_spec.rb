require "rails_helper"

RSpec.describe "models" do
  describe Asset do
    it "is valid from the factory" do
      expect(build(:asset)).to be_valid
    end

    it "requires a unique tag" do
      create(:asset, tag: "X1")
      expect(build(:asset, tag: "X1")).not_to be_valid
    end

    it "rejects bad category and status" do
      expect(build(:asset, category: "toaster")).not_to be_valid
      expect(build(:asset, status: "lost")).not_to be_valid
    end

    it "rejects warranty before purchase" do
      a = build(:asset, purchased_on: Date.new(2025, 1, 1), warranty_until: Date.new(2024, 1, 1))
      expect(a).not_to be_valid
      expect(a.errors[:warranty_until]).to be_present
    end

    it "allows a nil custodian and location" do
      expect(build(:asset, custodian: nil, location: nil)).to be_valid
    end

    it "searches by name, tag and serial" do
      a = create(:asset, name: "ThinkPad Zed", tag: "QQ-1", serial: "ABC123")
      create(:asset, name: "Other")
      expect(Asset.search("thinkpad")).to eq([a])
      expect(Asset.search("qq-1")).to eq([a])
      expect(Asset.search("abc12")).to eq([a])
    end
  end

  describe Person do
    it "requires a valid, case-insensitively unique email" do
      create(:person, email: "a@example.test")
      expect(build(:person, email: "A@example.test")).not_to be_valid
      expect(build(:person, email: "nope")).not_to be_valid
    end
  end

  describe Location do
    it("requires a unique name") do
      create(:location, name: "HQ")
      expect(build(:location, name: "HQ")).not_to be_valid
    end
  end

  describe Service do
    it "validates criticality and name" do
      expect(build(:service, criticality: "meh")).not_to be_valid
      expect(build(:service, name: nil)).not_to be_valid
    end
  end

  describe Dependency do
    let(:svc) { create(:service) }
    let(:asset) { create(:asset) }

    it "is valid between existing nodes" do
      expect(build(:dependency, source: svc, target: asset, kind: "runs_on")).to be_valid
    end

    it "rejects self edges, unknown kinds and missing nodes" do
      expect(build(:dependency, source: svc, target: svc)).not_to be_valid
      expect(build(:dependency, source: svc, target: asset, kind: "loves")).not_to be_valid
      expect(Dependency.new(source_type: "Service", source_id: 0, target_type: "Asset", target_id: asset.id)).not_to be_valid
    end

    it "rejects duplicates" do
      create(:dependency, source: svc, target: asset)
      expect(build(:dependency, source: svc, target: asset)).not_to be_valid
    end
  end

  describe Checkout do
    it "requires due after out" do
      expect(build(:checkout, due_at: Time.zone.parse("2025-12-01"))).not_to be_valid
    end

    it "blocks a second open checkout for the same asset" do
      c = create(:checkout)
      expect(build(:checkout, asset: c.asset)).not_to be_valid
      c.update!(in_at: c.out_at + 1.day)
      expect(build(:checkout, asset: c.asset)).to be_valid
    end
  end

  describe MaintenanceTask do
    it "validates kind and status" do
      expect(build(:maintenance_task)).to be_valid
      expect(build(:maintenance_task, kind: "x")).not_to be_valid
      expect(build(:maintenance_task, status: "x")).not_to be_valid
    end
  end
end
