require "rails_helper"

RSpec.describe "Agent runs API", type: :request do
  let(:key) { "sk-ant-api03-TESTKEY-#{SecureRandom.hex(12)}" }
  def json = JSON.parse(response.body)

  before do
    Api::AgentRunsController::RATE_LIMIT_STORE.clear
    travel_to Time.zone.parse("2026-11-05 10:00")
  end

  after { Api::AgentRunsController.client_factory = nil }

  def create_run(prompt, headers: {}, **extra)
    post "/api/agent/runs", params: { prompt: prompt, **extra }, headers: headers, as: :json
  end

  describe "replay mode (no key)" do
    it "replays a known prompt through the SSE pipeline" do
      create_run("What breaks if DB-Server goes down?")
      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("mode" => "replay", "recorded" => "synthetic", "replay_slug" => "db-server-outage",
                                      "status" => "queued", "stream_url" => "/api/agent/runs/#{json.dig('data', 'id')}/stream")

      get json.dig("data", "stream_url"), params: { speed: 100 }
      expect(response.media_type).to eq("text/event-stream")
      events = parse_sse(response.body)
      expect(event_sequence(events)).to eq(%w[progress tool_call tool_result text done])
      expect(events.select { |e, _| e == "text" }.size).to be > 10
      done = events.last.last
      expect(done).to include("status" => "succeeded", "mode" => "replay", "recorded" => "synthetic", "iterations" => 1)
      tool_result = events.find { |e, _| e == "tool_result" }.last
      expect(tool_result.dig("output", "data", "root", "name")).to eq("DB-Server")

      run = AgentRun.last
      expect(run.steps.map(&:kind)).to eq(%w[progress tool_use tool_result text])
      expect(run.steps.last.content).to eq(events.select { |e, _| e == "text" }.map { |_, d| d["delta"] }.join)
    end

    it "lists the replayable prompts when the prompt is unknown" do
      create_run("Write me a poem")
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("unknown_replay")
      expect(json["replays"].size).to eq(8)
      get "/api/agent/replays"
      expect(json["data"].map { |r| r["slug"] }).to include("fleet-summary")
    end

    it "re-streams a finished run from its stored steps" do
      create_run("Summarize the fleet")
      url = json.dig("data", "stream_url")
      get url, params: { speed: 100 }
      first = parse_sse(response.body)
      get url
      second = parse_sse(response.body)
      expect(event_sequence(second)).to eq(event_sequence(first))
      expect(second.select { |e, _| e == "text" }.size).to eq(1) # aggregated
      get "/api/agent/runs/#{AgentRun.last.id}"
      expect(json.dig("data", "steps").map { |s| s["kind"] }).to eq(%w[progress tool_use tool_result text])
    end

    it "refuses a second concurrent stream" do
      create_run("Summarize the fleet")
      AgentRun.last.update!(status: "running")
      get json.dig("data", "stream_url")
      expect(parse_sse(response.body)).to eq([["error", { "code" => "already_streaming", "message" => "This run is already being streamed." }]])
    end

    it "replays even with a key when mode=replay is requested" do
      create_run("Summarize the fleet", headers: { "x-anthropic-key" => key }, mode: "replay")
      expect(json.dig("data", "mode")).to eq("replay")
    end
  end

  describe "live mode (BYOK)" do
    let(:fake) do
      FakeAnthropic.client(
        FakeAnthropic.turn([{ type: :thinking, thinking: "Pulling the fleet numbers." },
                            { type: :tool_use, id: "toolu_1", name: "summarize_fleet", input: {} }]),
        FakeAnthropic.turn([{ type: :text, text: "You have 0 assets." }])
      )
    end

    before { Api::AgentRunsController.client_factory = ->(k) { (@keys_seen ||= []) << k; fake } }

    it "creates a live run and streams it when the key is on the stream request" do
      create_run("How many assets do we have?", headers: { "x-anthropic-key" => key })
      expect(json["data"]).to include("mode" => "live", "model" => "claude-opus-5-5", "recorded" => nil)
      url = json.dig("data", "stream_url")

      get url
      expect(response).to have_http_status(:unauthorized)
      expect(AgentRun.last.status).to eq("queued")

      get url, headers: { "x-anthropic-key" => key }
      events = parse_sse(response.body)
      expect(event_sequence(events)).to eq(%w[progress tool_call tool_result text done])
      expect(events.last.last).to include("status" => "succeeded", "mode" => "live", "iterations" => 1)
      expect(@keys_seen).to eq([key])
    end
  end

  describe "rate limiting" do
    it "limits run creation per key, with keyless requests limited per IP" do
      10.times { create_run("Summarize the fleet", headers: { "x-anthropic-key" => key }, mode: "replay") }
      expect(response).to have_http_status(:created)
      create_run("Summarize the fleet", headers: { "x-anthropic-key" => key }, mode: "replay")
      expect(response).to have_http_status(:too_many_requests)
      expect(json["error"]).to eq("rate_limited")

      create_run("Summarize the fleet", headers: { "x-anthropic-key" => "#{key}-other" }, mode: "replay")
      expect(response).to have_http_status(:created)
      create_run("Summarize the fleet")
      expect(response).to have_http_status(:created)
    end

    it "keys the limiter by a digest, never the key itself" do
      create_run("Summarize the fleet", headers: { "x-anthropic-key" => key }, mode: "replay")
      keys = Api::AgentRunsController::RATE_LIMIT_STORE.instance_variable_get(:@data).keys
      expect(keys.join).to include(Digest::SHA256.hexdigest(key))
      expect(keys.join).not_to include(key)
    end
  end
end
