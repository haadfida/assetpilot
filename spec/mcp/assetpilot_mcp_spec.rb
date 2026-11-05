require "rails_helper"

RSpec.describe AssetpilotMcp do
  READ_TOOLS = %w[search_assets get_asset impact_analysis summarize_fleet].freeze
  WRITE_TOOLS = %w[checkout_asset checkin_asset schedule_maintenance].freeze

  def rpc(server, method, params = nil, id: 1)
    body = { jsonrpc: "2.0", id: id, method: method }
    body[:params] = params if params
    JSON.parse(server.handle_json(body.to_json), symbolize_names: true)
  end

  def init(server)
    rpc(server, "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "rspec", version: "1" } })
  end

  def call_tool(server, name, args = {})
    rpc(server, "tools/call", { name: name, arguments: args })[:result]
  end

  let(:server) { described_class.build_server.tap { |s| init(s) } }
  let(:tools) { rpc(server, "tools/list")[:result][:tools].index_by { |t| t[:name] } }

  it "lists exactly the agent's tools, in registry order" do
    expect(rpc(server, "tools/list")[:result][:tools].map { |t| t[:name] }).to eq(Tools::Registry.names)
    expect(Tools::Registry.names).to match_array(READ_TOOLS + WRITE_TOOLS)
  end

  it "uses the agent tools' descriptions and full JSON schemas" do
    Tools::Registry::TOOLS.each do |source|
      listed = tools.fetch(source.tool_name)
      expect(listed[:description]).to eq(source.description)
      expect(listed[:inputSchema].deep_stringify_keys.except("$schema")).to eq(source.input_schema)
    end
  end

  it "marks read tools read-only and mutating tools as writes" do
    READ_TOOLS.each do |n|
      expect(tools[n][:annotations]).to include(readOnlyHint: true, destructiveHint: false)
    end
    WRITE_TOOLS.each { |n| expect(tools[n][:annotations]).to include(readOnlyHint: false) }
    expect(tools["checkout_asset"][:annotations][:destructiveHint]).to be(true)
    expect(tools["checkin_asset"][:annotations][:destructiveHint]).to be(true)
  end

  describe "tools/call" do
    let!(:person) { create(:person, email: "ada@example.com") }
    let!(:asset) { create(:asset, tag: "LAP-001", name: "Laptop One") }

    def payload(result) = JSON.parse(result[:content].first[:text])

    it "summarize_fleet" do
      result = call_tool(server, "summarize_fleet")
      expect(result[:isError]).to be(false)
      expect(payload(result)).to include("ok" => true)
      expect(payload(result)["data"]).to include("total_assets" => 1)
      expect(result[:structuredContent]).to eq(payload(result).deep_symbolize_keys)
    end

    it "search_assets and get_asset" do
      found = payload(call_tool(server, "search_assets", { query: "Laptop" }))
      expect(found["ok"]).to be(true)
      expect(found.to_s).to include("LAP-001")
      expect(payload(call_tool(server, "get_asset", { asset: "LAP-001" }))["data"].to_s).to include("Laptop One")
    end

    it "impact_analysis" do
      result = call_tool(server, "impact_analysis", { node_type: "asset", node: "LAP-001" })
      expect(result[:isError]).to be(false)
      expect(payload(result)).to eq(JSON.parse(JSON.generate(Tools::ImpactAnalysis.call({ "node_type" => "asset", "node" => "LAP-001" }))))
    end

    it "checkout, checkin and schedule_maintenance change data" do
      out = call_tool(server, "checkout_asset", { asset: "LAP-001", person: "ada@example.com", due_on: (Time.zone.today + 7).iso8601 })
      expect(payload(out)["ok"]).to be(true), -> { out.inspect }
      expect(asset.reload.status).to eq("checked_out")

      back = call_tool(server, "checkin_asset", { asset: "LAP-001" })
      expect(payload(back)["ok"]).to be(true), -> { back.inspect }
      expect(asset.reload.status).to eq("available")

      sched = call_tool(server, "schedule_maintenance", { assets: ["LAP-001"], due_on: (Time.zone.today + 14).iso8601, kind: MaintenanceTask::KINDS.first })
      expect(payload(sched)["ok"]).to be(true), -> { sched.inspect }
      expect(asset.maintenance_tasks.count).to eq(1)
    end

    it "returns tool errors as isError results with the agent's structured error" do
      result = call_tool(server, "get_asset", { asset: "NOPE-1" })
      expect(result[:isError]).to be(true)
      expect(payload(result).dig("error", "code")).to eq("not_found")
      bad = call_tool(server, "checkout_asset", { asset: "LAP-001" })
      expect(bad[:isError]).to be(true) # the SDK rejects the missing required arguments before the tool runs
      wrong = call_tool(server, "checkout_asset", { asset: "LAP-001", person: "ada@example.com", due_on: "not-a-date" })
      expect(wrong[:isError]).to be(true)
      expect(payload(wrong).dig("error", "code")).to eq("invalid_input")
    end
  end

  it "serves inventory://summary" do
    expect(rpc(server, "resources/list")[:result][:resources].map { |r| r[:uri] }).to eq(["inventory://summary"])
    text = rpc(server, "resources/read", { uri: "inventory://summary" })[:result][:contents].first[:text]
    expect(JSON.parse(text)).to include("ok" => true)
  end

  describe "read-only mode" do
    let(:server) { described_class.build_server(allow_writes: false).tap { |s| init(s) } }

    it "exposes only read tools" do
      expect(tools.keys).to match_array(READ_TOOLS)
    end

    it "refuses mutating calls" do
      result = rpc(server, "tools/call", { name: "checkout_asset", arguments: {} })
      expect(result[:error] || result.dig(:result, :isError)).to be_truthy
    end
  end
end
