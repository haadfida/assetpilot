require "rails_helper"

RSpec.describe AgentRun do
  let(:run) { AgentRun.create!(prompt: "Summarize the fleet", model: "claude-opus-5-5", mode: "live") }

  it "validates mode, status and replay slug" do
    expect(AgentRun.new(prompt: "x", model: "m", mode: "dream")).not_to be_valid
    expect(AgentRun.new(prompt: "x", model: "m", mode: "replay")).not_to be_valid
    expect(AgentRun.new(prompt: "x", model: "m", mode: "replay", replay_slug: "s")).to be_valid
  end

  it "claims a queued run exactly once" do
    expect(run.claim!).to be(true)
    expect(run.status).to eq("running")
    expect(run.started_at).to be_present
    expect(AgentRun.find(run.id).claim!).to be(false)
  end

  it "keeps steps ordered and unique per position" do
    run.steps.create!(position: 1, kind: "tool_use", tool_use_id: "t1", tool_name: "get_asset", input: { "asset" => "A" })
    run.steps.create!(position: 0, kind: "text", content: "hi")
    expect(run.steps.reload.map(&:kind)).to eq(%w[text tool_use])
    expect { run.steps.create!(position: 1, kind: "text") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { AgentStep.create!(agent_run: run, position: 2, kind: "tool_result") }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
