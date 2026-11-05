require "rails_helper"

# Live mode end to end with a scripted model (FakeAnthropic): the real Agent::Runner, tools, sandbox,
# grader and report. No network.
RSpec.describe Evals::Live do
  let(:cases) { Evals.load_cases.index_by(&:id) }

  def tool_use(name, input, id) = { type: :tool_use, id: id, name: name, input: input }

  it "runs each case through Agent::Runner in a rolled-back sandbox and grades it" do
    client = FakeAnthropic.client(
      # checkin-ap-00014: correct
      FakeAnthropic.turn([{ type: :thinking, thinking: "Checking in AP-00014." }, tool_use("checkin_asset", { "asset" => "AP-00014" }, "t1")]),
      FakeAnthropic.turn([{ type: :text, text: "Done: AP-00014 is back from Lonny Harvey." }]),
      # impact-db-server: wrong node
      FakeAnthropic.turn([tool_use("impact_analysis", { "node_type" => "asset", "node" => "Backup-NAS" }, "t2")]),
      FakeAnthropic.turn([{ type: :text, text: "12 services, Billing API first." }])
    )
    selected = [cases.fetch("checkin-ap-00014"), cases.fetch("impact-db-server")]

    results = nil
    expect do
      results = described_class.new(selected, api_key: "sk-test", client: client, log: nil).run
    end.not_to(change { [AgentRun.count, Checkout.count, Asset.count] })

    ok, bad = results
    expect(ok).to have_attributes(status: "graded", pass: true)
    expect(ok.transcript.calls.map(&:name)).to eq(["checkin_asset"])
    expect(ok.transcript.final_text).to eq("Done: AP-00014 is back from Lonny Harvey.")
    expect(ok.db.map(&:pass)).to all(be(true))
    expect(bad.pass).to be(false)
    expect(bad.grade.dimensions).to include("tools" => true, "args" => false)

    # Each case saw the seeded data at AS_OF in the user turn.
    expect(client.requests.first[:messages].first[:content]).to start_with("Today's date: 2026-11-05.")

    report = Evals::Report.new(mode: "live", cases: selected, results: results, meta: { "model" => "claude-opus-5-5" })
    expect(report.summary).to include("cases" => 2, "passed" => 1, "errors" => 0)
    expect(report.summary["by_dimension"]).to include("tools" => 2, "args" => 1)
    expect(report.table).to include("| write | 1 | 1 | 100% |", "`impact-db-server`")
    expect(report.as_json["cases"].first["transcript"]["calls"].first).to include("name" => "checkin_asset", "ok" => true)
  end

  it "records an API failure as an error, not a failed grade, and aborts on a rejected key" do
    err = Anthropic::Errors::AuthenticationError.new(url: URI("https://api.anthropic.com/v1/messages"), status: 401,
                                                     headers: {}, body: nil, request: nil, response: nil, message: "bad key")
    client = FakeAnthropic.client(FakeAnthropic.turn(raise_error: err))
    expect do
      described_class.new([cases.fetch("fleet-summary")], api_key: "sk-bad", client: client, log: nil).run
    end.to raise_error(described_class::Abort, /invalid_api_key/)

    overloaded = Anthropic::Errors::InternalServerError.new(url: URI("https://api.anthropic.com/v1/messages"), status: 529,
                                                            headers: {}, body: nil, request: nil, response: nil, message: "overloaded")
    client = FakeAnthropic.client(FakeAnthropic.turn(raise_error: overloaded))
    result = described_class.new([cases.fetch("fleet-summary")], api_key: "sk-x", client: client, log: nil).run.sole
    expect(result).to have_attributes(status: "error", pass: false)
    expect(result.error).to start_with("api_error")
  end
end
