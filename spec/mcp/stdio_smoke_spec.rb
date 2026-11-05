require "rails_helper"
require "open3"

# Spawns bin/mcp as a real subprocess (test env) and speaks JSON-RPC over its stdin/stdout.
RSpec.describe "bin/mcp stdio smoke test" do
  it "handles initialize, tools/list and tools/call" do
    requests = [
      { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "smoke", version: "1" } } },
      { jsonrpc: "2.0", method: "notifications/initialized" },
      { jsonrpc: "2.0", id: 2, method: "tools/list" },
      { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "summarize_fleet", arguments: {} } }
    ]
    env = { "RAILS_ENV" => "test", "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s }
    out, err, status = Bundler.with_unbundled_env do
      Open3.capture3(env, Rails.root.join("bin/mcp").to_s, stdin_data: requests.map(&:to_json).join("\n") + "\n", chdir: Rails.root.to_s)
    end

    lines = out.lines.map(&:strip).reject(&:empty?)
    responses = lines.map { |l| JSON.parse(l) } # raises if anything but JSON-RPC reached stdout
    by_id = responses.index_by { |r| r["id"] }

    expect(by_id[1].dig("result", "serverInfo", "name")).to eq("assetpilot")
    expect(by_id[2].dig("result", "tools").map { |t| t["name"] }).to eq(Tools::Registry.names)
    call = by_id[3]["result"]
    expect(call["isError"]).to be(false)
    expect(JSON.parse(call["content"].first["text"])).to include("ok" => true)
    expect(status).to be_success, -> { err }
  end
end
