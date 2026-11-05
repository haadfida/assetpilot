require "rails_helper"

RSpec.describe Agent::Runner do
  let(:run) { AgentRun.create!(prompt: "Which laptops are overdue?", model: "claude-opus-5-5", mode: "live") }
  let(:events) { [] }
  let(:recorder) { Agent::Recorder.new(run, emit: ->(e, d) { events << [e, d.as_json] }) }
  let(:config) { Agent::Config.current }

  def run_with(client, key: nil)
    described_class.new(run: run, client: client, recorder: recorder, config: config).call(api_key: key)
    run.reload
  end

  def tool_use(name, input, id: "toolu_#{name}") = { type: :tool_use, id: id, name: name, input: input }

  before do
    travel_to Time.zone.parse("2026-11-05 10:00")
    laptop = create(:asset, tag: "L-1", name: "ThinkPad", category: "laptop", status: "checked_out")
    create(:checkout, asset: laptop, person: create(:person, name: "Ann Lee"), out_at: 20.days.ago, due_at: 6.days.ago)
  end

  describe "tool-selection loop" do
    let(:client) do
      FakeAnthropic.client(
        FakeAnthropic.turn([{ type: :thinking, thinking: "Looking up overdue laptops." },
                            tool_use("search_assets", { category: "laptop", overdue: true })],
                           usage: { input_tokens: 1000, output_tokens: 50, cache_read_input_tokens: 0, cache_creation_input_tokens: 900 }),
        FakeAnthropic.turn([{ type: :text, text: "One laptop is overdue: L-1, with Ann Lee." }],
                           usage: { input_tokens: 1200, output_tokens: 30, cache_read_input_tokens: 900, cache_creation_input_tokens: 0 })
      )
    end

    it "runs the tool the model picked, sends the result back, and finishes on end_turn" do
      run_with(client)
      expect(run).to have_attributes(status: "succeeded", stop_reason: "end_turn", iterations: 1,
                                     input_tokens: 2200, output_tokens: 80, cache_read_input_tokens: 900,
                                     cache_creation_input_tokens: 900)

      second = client.requests.last[:messages]
      expect(second.map { |m| m[:role] }).to eq(%w[user assistant user])
      # Assistant turn goes back unchanged, thinking signature included.
      expect(second[1][:content].first).to include(type: "thinking", thinking: "Looking up overdue laptops.")
      expect(second[1][:content].first[:signature]).to start_with("sig-")
      result = second[2][:content].sole
      expect(result).to include(type: "tool_result", tool_use_id: "toolu_search_assets", is_error: false)
      expect(JSON.parse(result[:content]).dig("data", "assets", 0, "tag")).to eq("L-1")
    end

    it "persists ordered steps: progress, tool_use with input, tool_result with output, aggregated text" do
      run_with(client)
      steps = run.steps.to_a
      expect(steps.map(&:kind)).to eq(%w[progress tool_use tool_result text])
      expect(steps.map(&:position)).to eq([0, 1, 2, 3])
      expect(steps[1].input).to eq("category" => "laptop", "overdue" => true)
      expect(steps[2].output.dig("data", "total")).to eq(1)
      expect(steps[3].content).to eq("One laptop is overdue: L-1, with Ann Lee.")
      expect(steps.map(&:iteration)).to eq([0, 1, 1, 1])
      expect(events.map(&:first).uniq).to eq(%i[progress tool_call tool_result text done])
      expect(events.count { |e, _| e == :text }).to be > 1 # deltas streamed, one row stored
    end

    it "sends the request shape the claude-api skill prescribes for Opus 5.5" do
      run_with(client)
      req = client.requests.first
      expect(req).to include(model: "claude-opus-5-5", max_tokens: 64_000, tool_choice: { type: "auto" },
                             thinking: { type: "adaptive", display: "updates" }, output_config: { effort: "medium" },
                             fallbacks: :default, cache_control: { type: "ephemeral" },
                             betas: %w[server-side-fallback-2026-07-01 thinking-display-updates-2026-08-18])
      expect(req[:system_]).to include("AssetPilot")
      expect(req[:messages].first[:content]).to start_with("Today's date: 2026-11-05.")
      expect(req[:tools].map { |t| t[:name] }).to eq(Tools::Registry.names)
      expect(req[:tools]).to all(include(strict: true, eager_input_streaming: true))
    end
  end

  it "returns every result of a parallel tool turn in one user message" do
    client = FakeAnthropic.client(
      FakeAnthropic.turn([tool_use("summarize_fleet", {}, id: "t1"), tool_use("get_asset", { asset: "L-1" }, id: "t2")]),
      FakeAnthropic.turn([{ type: :text, text: "Done." }])
    )
    run_with(client)
    results = client.requests.last[:messages].last[:content]
    expect(results.map { |r| r[:tool_use_id] }).to eq(%w[t1 t2])
    expect(run.steps.map(&:kind)).to eq(%w[tool_use tool_result tool_use tool_result text])
  end

  describe "error handling" do
    it "returns tool errors to the model as is_error results and keeps going" do
      client = FakeAnthropic.client(
        FakeAnthropic.turn([tool_use("checkin_asset", { asset: "NOPE-1" })]),
        FakeAnthropic.turn([tool_use("checkout_asset", { asset: "L-1" }, id: "t2")]), # missing fields
        FakeAnthropic.turn([tool_use("format_disk", {}, id: "t3")]),
        FakeAnthropic.turn([{ type: :text, text: "I could not do that." }])
      )
      run_with(client)
      expect(run.status).to eq("succeeded")
      codes = run.steps.where(kind: "tool_result").map { |s| [s.is_error, s.output.dig("error", "code")] }
      expect(codes).to eq([[true, "not_found"], [true, "invalid_input"], [true, "unknown_tool"]])
      expect(client.requests.last[:messages][-1][:content].sole).to include(is_error: true)
    end

    it "does not run a tool whose eager-streamed input is not valid JSON" do
      client = FakeAnthropic.client(
        FakeAnthropic.turn([tool_use("checkin_asset", '{"asset": "L-1')]),
        FakeAnthropic.turn([{ type: :text, text: "Retrying failed." }])
      )
      expect(Tools::Registry).not_to receive(:call)
      run_with(client)
      result = client.requests.last[:messages].last[:content].sole
      expect(result).to include(is_error: true)
      expect(JSON.parse(result[:content])).to eq("INVALID_JSON" => '{"asset": "L-1')
      expect(client.requests.last[:messages][1][:content].sole[:input]).to eq({})
      expect(Checkout.open.count).to eq(1)
    end

    it "stops on a refusal without running that turn's tools" do
      client = FakeAnthropic.client(FakeAnthropic.turn([tool_use("checkin_asset", { asset: "L-1" })],
                                                       stop_reason: :refusal, stop_details: { category: "cyber" }))
      run_with(client)
      expect(run).to have_attributes(status: "refused", error_code: "refusal", stop_reason: "refusal")
      expect(run.error_message).to include("cyber")
      expect(Checkout.open.count).to eq(1)
      expect(run.steps.map(&:kind)).to eq(%w[error])
    end

    it "does not run a tool cut off by max_tokens" do
      client = FakeAnthropic.client(FakeAnthropic.turn([tool_use("checkin_asset", { asset: "L-1" })], stop_reason: :max_tokens))
      run_with(client)
      expect(run).to have_attributes(status: "failed", error_code: "max_tokens")
      expect(Checkout.open.count).to eq(1)
    end

    it "maps API errors to a failed run and never stores the key" do
      key = "sk-ant-api03-SECRET-#{SecureRandom.hex(8)}"
      err = Anthropic::Errors::APIStatusError.for(url: URI("https://api.anthropic.com/v1/messages"), status: 401, headers: {},
                                                  body: { "error" => { "message" => "bad key #{key}" } },
                                                  request: nil, response: nil, message: "invalid x-api-key #{key}")
      run_with(FakeAnthropic.client(FakeAnthropic.turn(raise_error: err)), key: key)
      expect(run).to have_attributes(status: "failed", error_code: "invalid_api_key")
      expect(run.error_message).not_to include(key)

      overloaded = Anthropic::Errors::APIStatusError.for(url: URI("https://api.anthropic.com/v1/messages"), status: 529,
                                                         headers: {}, body: nil, request: nil, response: nil, message: "Overloaded #{key}")
      other = AgentRun.create!(prompt: "x", model: "m", mode: "live")
      described_class.new(run: other, client: FakeAnthropic.client(FakeAnthropic.turn(raise_error: overloaded)),
                          recorder: Agent::Recorder.new(other)).call(api_key: key)
      expect(other.reload).to have_attributes(status: "failed", error_code: "api_error")
      expect(other.error_message).to include("529").and(include("[FILTERED]"))
      expect(other.error_message).not_to include(key)
    end

    it "maps connection errors and unexpected exceptions" do
      conn = Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com/v1/messages"))
      run_with(FakeAnthropic.client(FakeAnthropic.turn(raise_error: conn)))
      expect(run.error_code).to eq("connection_error")

      boom = AgentRun.create!(prompt: "x", model: "m", mode: "live")
      described_class.new(run: boom, client: FakeAnthropic.client(FakeAnthropic.turn(raise_error: RuntimeError.new("kaboom"))),
                          recorder: Agent::Recorder.new(boom)).call
      expect(boom.reload).to have_attributes(status: "failed", error_code: "internal_error")
      expect(boom.error_message).not_to include("kaboom")
    end
  end

  describe "iteration cap" do
    let(:config) { Agent::Config.current.tap { |c| c.max_tool_iterations = 3 } }

    it "stops a model that keeps calling tools" do
      client = FakeAnthropic.client(FakeAnthropic.turn([tool_use("summarize_fleet", {})]), repeat_last: true)
      run_with(client)
      expect(client.requests.size).to eq(3)
      expect(run).to have_attributes(status: "max_iterations", iterations: 3, error_code: "iteration_cap")
      expect(run.steps.where(kind: "tool_result").count).to eq(3)
      expect(run.steps.last.kind).to eq("error")
      expect(events.last.first).to eq(:done)
    end
  end
end
