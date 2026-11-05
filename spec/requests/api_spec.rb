require "rails_helper"

RSpec.describe "API", type: :request do
  def json = JSON.parse(response.body)

  describe "GET /api/assets" do
    before do
      create(:asset, tag: "A-1", name: "Dell Latitude", category: "laptop", status: "available")
      create(:asset, tag: "A-2", name: "Dell Monitor", category: "monitor", status: "checked_out")
      create(:asset, tag: "A-3", name: "HP Printer", category: "printer", status: "available", serial: "ZZ99")
    end

    it "lists with pagination meta" do
      get "/api/assets", params: { per_page: 2 }
      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(2)
      expect(json["meta"]).to include("total" => 3, "total_pages" => 2, "page" => 1, "per_page" => 2)
      get "/api/assets", params: { per_page: 2, page: 2 }
      expect(json["data"].map { |a| a["tag"] }).to eq(["A-3"])
    end

    it "searches with q" do
      get "/api/assets", params: { q: "dell" }
      expect(json["data"].map { |a| a["tag"] }).to eq(%w[A-1 A-2])
      get "/api/assets", params: { q: "zz99" }
      expect(json["data"].map { |a| a["tag"] }).to eq(["A-3"])
    end

    it "treats LIKE wildcards in q literally" do
      get "/api/assets", params: { q: "%" }
      expect(json["data"]).to be_empty
    end

    it "filters by status and category" do
      get "/api/assets", params: { status: "available", category: "printer" }
      expect(json["data"].map { |a| a["tag"] }).to eq(["A-3"])
    end

    it "caps per_page" do
      get "/api/assets", params: { per_page: 5000 }
      expect(json["meta"]["per_page"]).to eq(100)
    end

    it "rejects a bad warranty_before" do
      get "/api/assets", params: { warranty_before: "nope" }
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/assets/:id" do
    it "shows an asset with open checkout and maintenance" do
      c = create(:checkout)
      create(:maintenance_task, asset: c.asset)
      get "/api/assets/#{c.asset_id}"
      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("tag" => c.asset.tag)
      expect(json["data"]["open_checkout"]["person_id"]).to eq(c.person_id)
      expect(json["data"]["maintenance_tasks"].size).to eq(1)
    end

    it "404s" do
      get "/api/assets/0"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "people and services" do
    it "lists and shows people" do
      p = create(:person, department: "Ops")
      create(:asset, custodian: p)
      get "/api/people", params: { department: "Ops" }
      expect(json["data"].map { |x| x["id"] }).to eq([p.id])
      get "/api/people/#{p.id}"
      expect(json["data"]["custodied_asset_ids"].size).to eq(1)
      get "/api/people/0"
      expect(response).to have_http_status(:not_found)
    end

    it "lists and shows services" do
      s = create(:service, criticality: "critical", owner: create(:person, name: "Ada"))
      create(:service, criticality: "low")
      get "/api/services", params: { criticality: "critical" }
      expect(json["data"].map { |x| x["id"] }).to eq([s.id])
      get "/api/services/#{s.id}"
      expect(json["data"]["owner_name"]).to eq("Ada")
    end
  end

  describe "GET /api/impact/:type/:id" do
    let(:owner) { create(:person) }
    let(:srv) { create(:asset, category: "server") }
    let(:svc_a) { create(:service, owner: owner) }
    let(:svc_b) { create(:service) }

    before do
      create(:dependency, source: svc_a, target: srv, kind: "runs_on")
      create(:dependency, source: svc_b, target: svc_a)
      create(:dependency, source: svc_a, target: svc_b) # cycle
    end

    it "returns dependents, people and counts despite the cycle" do
      get "/api/impact/asset/#{srv.id}"
      expect(response).to have_http_status(:ok)
      expect(json["root"]).to include("type" => "Asset", "id" => srv.id)
      expect(json["services"].map { |s| [s["id"], s["depth"]] }).to eq([[svc_a.id, 1], [svc_b.id, 2]])
      expect(json["people"].map { |p| p["id"] }).to eq([owner.id])
      expect(json["counts"]).to eq("services" => 2, "assets" => 0, "people" => 1)
    end

    it "honours max_depth" do
      get "/api/impact/asset/#{srv.id}", params: { max_depth: 1 }
      expect(json["services"].map { |s| s["id"] }).to eq([svc_a.id])
    end

    it "404s for unknown ids and 404s for unknown types" do
      get "/api/impact/asset/0"
      expect(response).to have_http_status(:not_found)
      get "/api/impact/person/1"
      expect(response).to have_http_status(:not_found)
    end
  end
end
