require "rails_helper"

RSpec.describe Agent::Replayer do
  let(:replay) { Agent::Replays.find("dc1-warranty-maintenance") }
  let(:run) { AgentRun.create!(prompt: replay.prompt, model: replay.model, mode: "replay", replay_slug: replay.slug, recorded: replay.recorded) }
  let(:events) { [] }
  let(:recorder) { Agent::Recorder.new(run, emit: ->(e, d) { events << [e, d.as_json] }) }
  let(:sleeps) { [] }

  def replay!(speed)
    described_class.new(run: run, replay: replay, recorder: recorder, speed: speed, sleeper: ->(s) { sleeps << s }).call
    run.reload
  end

  it "re-emits the recording with its timings divided by speed" do
    replay!(4)
    expect(sleeps.sum).to be_within(0.05).of(replay.duration_ms / 1000.0 / 4)
    expect(event_sequence(events)).to eq(%i[progress tool_call tool_result progress tool_call tool_result text done])
  end

  it "persists the same steps as the recording and finishes with its status and usage" do
    replay!(50)
    expect(run.steps.map(&:kind)).to eq(replay.steps.map { |s| s["type"] == "tool_use" ? "tool_use" : s["type"] })
    expect(run.steps.where(kind: "text").sole.content).to eq(replay.steps.last["text"])
    expect(run.steps.where(kind: "tool_result").map(&:output)).to eq(replay.steps.select { |s| s["type"] == "tool_result" }.map { |s| s["output"] })
    expect(run).to have_attributes(status: "succeeded", iterations: 2, mode: "replay", recorded: "synthetic",
                                   output_tokens: replay.usage[:output_tokens])
  end

  it "does not execute tools or touch the inventory" do
    expect(Tools::Registry).not_to receive(:call)
    expect { replay!(50) }.not_to change(MaintenanceTask, :count)
  end

  it "skips the waits once the client is gone, but still persists the run" do
    gone = Agent::Recorder.new(run, emit: ->(*) { raise ActionController::Live::ClientDisconnected })
    described_class.new(run: run, replay: replay, recorder: gone, sleeper: ->(s) { sleeps << s }).call
    expect(sleeps.size).to eq(1) # only the wait before the first event, which is what detects the disconnect
    expect(run.reload.status).to eq("succeeded")
    expect(run.steps.count).to eq(replay.steps.size)
  end
end
