require "rails_helper"

RSpec.describe Agent::Replays do
  it "ships eight synthetic recordings" do
    expect(described_class.all.size).to eq(8)
    expect(described_class.all.map(&:recorded).uniq).to eq(["synthetic"])
  end

  it "matches prompts loosely (case, punctuation, aliases)" do
    expect(described_class.find_by_prompt("what breaks if db-server goes down")&.slug).to eq("db-server-outage")
    expect(described_class.find_by_prompt("Fleet summary!")&.slug).to eq("fleet-summary")
    expect(described_class.find_by_prompt("delete everything")).to be_nil
  end

  it "has well-formed, schema-valid tool calls with a result for each" do
    described_class.all.each do |r|
      uses = r.steps.select { |s| s["type"] == "tool_use" }
      results = r.steps.select { |s| s["type"] == "tool_result" }
      expect(uses.map { |u| u["id"] }).to eq(results.map { |x| x["tool_use_id"] }), r.slug
      uses.each do |u|
        expect(Tools::Registry.fetch(u["name"]).schemer.valid?(u["input"])).to be(true), "#{r.slug} #{u['id']}"
      end
      expect(r.steps.map { |s| s["t_ms"] }).to eq(r.steps.map { |s| s["t_ms"] }.sort), r.slug
      expect(r.steps.last["type"]).to eq("text")
    end
  end
end
