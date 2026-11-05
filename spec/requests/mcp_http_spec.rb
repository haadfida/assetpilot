require "rails_helper"

RSpec.describe "MCP over HTTP at /mcp", type: :request do
  let(:headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json, text/event-stream" } }

  before { host! "localhost" } # the transport rejects unknown Host headers (DNS rebinding protection)

  def rpc(method, params = nil, extra = {})
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.compact.to_json, headers: headers.merge(extra)
  end

  it "lists only the read tools by default" do
    rpc("tools/list")
    expect(response).to have_http_status(:ok)
    names = JSON.parse(response.body).dig("result", "tools").map { |t| t["name"] }
    expect(names).to match_array(%w[search_assets get_asset impact_analysis summarize_fleet])
  end

  it "calls a tool" do
    rpc("tools/call", { name: "summarize_fleet", arguments: {} })
    expect(JSON.parse(response.body).dig("result", "isError")).to be(false)
  end

  describe "auth and writes" do
    around do |ex|
      old = ENV.slice("MCP_TOKEN", "MCP_ALLOW_WRITES")
      ENV["MCP_TOKEN"] = "s3cret"
      ENV["MCP_ALLOW_WRITES"] = "1"
      Rails.application.reload_routes!
      ex.run
    ensure
      %w[MCP_TOKEN MCP_ALLOW_WRITES].each { |k| old.key?(k) ? ENV[k] = old[k] : ENV.delete(k) }
      Rails.application.reload_routes!
    end

    it "requires the bearer token" do
      rpc("tools/list")
      expect(response).to have_http_status(:unauthorized)
      rpc("tools/list", nil, "HTTP_AUTHORIZATION" => "Bearer wrong")
      expect(response).to have_http_status(:unauthorized)
    end

    it "exposes write tools when MCP_ALLOW_WRITES=1" do
      rpc("tools/list", nil, "HTTP_AUTHORIZATION" => "Bearer s3cret")
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("result", "tools").size).to eq(7)
    end
  end
end
