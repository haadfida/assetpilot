require "rails_helper"

# End to end with the real Anthropic SDK client; the Messages API is stubbed with WebMock.
RSpec.describe "Agent BYOK", type: :request do
  let(:key) { "sk-ant-api03-BYOK-#{SecureRandom.hex(16)}" }
  let(:log) { StringIO.new }
  let(:capture) { ActiveSupport::Logger.new(log).tap { |l| l.level = :debug } }
  let(:messages_url) { "https://api.anthropic.com/v1/messages" }
  let(:signature) { "EqQBCkYIBRgCIkBvZXBhcXVlLXNpZ25hdHVyZQ==" }

  before do
    Api::AgentRunsController::RATE_LIMIT_STORE.clear
    Rails.logger.broadcast_to(capture)
    create(:asset, tag: "L-1", name: "ThinkPad", category: "laptop")
    stub_request(:post, messages_url).to_return(
      AnthropicSse.response([{ type: "thinking", thinking: "Looking up L-1.", signature: signature },
                             { type: "tool_use", id: "toolu_01ABC", name: "get_asset", input: { asset: "L-1" } }],
                            stop_reason: "tool_use"),
      AnthropicSse.response([{ type: "text", text: "L-1 is a ThinkPad and it is available." }], stop_reason: "end_turn")
    )
  end

  after { Rails.logger.stop_broadcasting_to(capture) }

  def all_rows_json
    conn = ActiveRecord::Base.connection
    conn.tables.map { |t| conn.select_all("SELECT * FROM #{conn.quote_table_name(t)}").to_a.to_json }.join
  end

  it "uses the header key for the API call and never logs or stores it" do
    # Sending the key as a parameter by mistake: it must be filtered from the log too.
    post "/api/agent/runs", params: { prompt: "Tell me about L-1", "x-anthropic-key" => key }.to_json,
                            headers: { "x-anthropic-key" => key, "Content-Type" => "application/json" }
    expect(response).to have_http_status(:created)
    get "/api/agent/runs/#{AgentRun.last.id}/stream", headers: { "x-anthropic-key" => key }
    sse = response.body
    events = parse_sse(sse)

    expect(event_sequence(events)).to eq(%w[progress tool_call tool_result text done])
    expect(events.last.last).to include("status" => "succeeded", "iterations" => 1)
    expect(events.find { |e, _| e == "tool_result" }.last.dig("output", "data", "name")).to eq("ThinkPad")

    # The key was used, and only as the API credential (anthropic 2.5 sends api_key as a Bearer token).
    expect(a_request(:post, messages_url).with(headers: { "Authorization" => "Bearer #{key}" })).to have_been_made.twice

    expect(log.string).to include("[FILTERED]")
    expect(log.string).not_to include(key)
    expect(all_rows_json).not_to include(key)
    expect(all_rows_json).to include("Tell me about L-1") # sanity: the scan sees the run
    expect(sse).not_to include(key)
  end

  it "sends the skill's request shape and echoes the thinking block back unchanged" do
    post "/api/agent/runs", params: { prompt: "Tell me about L-1" }, headers: { "x-anthropic-key" => key }, as: :json
    get "/api/agent/runs/#{AgentRun.last.id}/stream", headers: { "x-anthropic-key" => key }

    bodies = []
    expect(a_request(:post, messages_url).with do |req|
      bodies << JSON.parse(req.body)
      betas = req.headers["Anthropic-Beta"].to_s.split(",").map(&:strip)
      betas.include?("server-side-fallback-2026-07-01") && betas.include?("thinking-display-updates-2026-08-18")
    end).to have_been_made.twice

    first, second = bodies
    expect(first).to include("model" => "claude-opus-5-5", "max_tokens" => 64_000, "stream" => true,
                             "thinking" => { "type" => "adaptive", "display" => "updates" },
                             "output_config" => { "effort" => "medium" }, "fallbacks" => "default",
                             "tool_choice" => { "type" => "auto" }, "cache_control" => { "type" => "ephemeral" })
    expect(first).not_to have_key("betas")
    expect(first["tools"]).to all(include("strict" => true, "eager_input_streaming" => true))
    expect(first["tools"].map { |t| t["name"] }).to eq(Tools::Registry.names)

    expect(second["messages"][1]).to eq("role" => "assistant", "content" => [
      { "type" => "thinking", "thinking" => "Looking up L-1.", "signature" => signature },
      { "type" => "tool_use", "id" => "toolu_01ABC", "name" => "get_asset", "input" => { "asset" => "L-1" } }
    ])
    result = second["messages"][2]["content"].sole
    expect(result).to include("type" => "tool_result", "tool_use_id" => "toolu_01ABC", "is_error" => false)
  end

  it "reports a rejected key as a failed run without echoing it" do
    WebMock.reset!
    stub_request(:post, messages_url).to_return(status: 401, headers: { "Content-Type" => "application/json" },
                                                body: { type: "error", error: { type: "authentication_error", message: "invalid x-api-key" } }.to_json)
    post "/api/agent/runs", params: { prompt: "Tell me about L-1" }, headers: { "x-anthropic-key" => key }, as: :json
    get "/api/agent/runs/#{AgentRun.last.id}/stream", headers: { "x-anthropic-key" => key }
    events = parse_sse(response.body)
    expect(events.map(&:first)).to eq(%w[error done])
    expect(events.first.last["code"]).to eq("invalid_api_key")
    expect(AgentRun.last).to have_attributes(status: "failed", error_code: "invalid_api_key")
    expect(log.string + all_rows_json + response.body).not_to include(key)
  end
end
