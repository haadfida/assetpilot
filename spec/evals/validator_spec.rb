require "rails_helper"

RSpec.describe Evals::Validator do
  def report_for(raw) = described_class.new([Evals::Case.new(raw.deep_stringify_keys)]).run.sole

  let(:good) do
    { id: "t-fleet", prompt: "Summarize the fleet", tags: ["read"],
      expected_tools: { order: "ordered", calls: [{ name: "summarize_fleet" }] },
      answer: { includes: ["506"] }, oracle: { calls: [{ name: "summarize_fleet", input: {} }], answer: "506 assets." } }
  end

  it "passes every case in evals/cases.jsonl (the offline eval run)" do
    reports = described_class.new(Evals.load_cases).run
    expect(reports.size).to be >= 40
    expect(reports.reject(&:pass).map { |r| [r.kase.id, r.problems] }).to eq([])
    expect(reports.map { |r| r.kase.id }.uniq.size).to eq(reports.size)
    expect(reports.count(&:replay)).to eq(Agent::Replays.all.size) # every recorded replay is graded by some case
  end

  it "covers every tag" do
    expect(Evals.load_cases.flat_map(&:tags).uniq).to match_array(Evals::TAGS)
  end

  it "accepts a well-formed case" do
    expect(report_for(good).problems).to eq([])
  end

  {
    "unknown tags" => ->(c) { c[:tags] = ["reads"] },
    "unknown tool" => ->(c) { c[:expected_tools][:calls] = [{ name: "delete_asset" }] },
    "has no argument" => ->(c) { c[:expected_tools][:calls] = [{ name: "summarize_fleet", args: { site: "x" } }] },
    "violates its schema" => ->(c) { c[:expected_tools][:calls] = [{ name: "search_assets", args: { category: "laptops" } }] },
    "does not compile" => ->(c) { c[:expected_tools][:calls] = [{ name: "summarize_fleet", args: { location: { regex: "(" } } }] },
    "outcome must be" => ->(c) { c[:expected_tools][:calls] = [{ name: "summarize_fleet", outcome: { error: "boom" } }] },
    "needs expected_outcome.db" => ->(c) { c[:tags] = ["write"] },
    "is missing in the seed data, expected exists" => ->(c) { c[:refs] = { assets: { "AP-77777" => "exists" } } },
    "oracle fails" => ->(c) { c[:oracle][:answer] = "Lots of assets." },
    "input fails the" => ->(c) { c[:oracle][:calls] = [{ name: "summarize_fleet", input: { site: "x" } }] },
    "empty transcript passes" => ->(c) { c[:expected_tools][:calls] = []; c.delete(:answer); c[:oracle] = { calls: [], answer: "" } },
    "unknown db assertion" => ->(c) { c[:expected_outcome] = { db: [{ type: "row_count" }] } },
    "not a seeded asset tag" => ->(c) { c[:expected_outcome] = { db: [{ type: "asset_status", asset: "AP-77777", equals: "available" }] } }
  }.each do |message, mutate|
    it "reports a case whose #{message}" do
      raw = good.deep_dup
      mutate.call(raw)
      expect(report_for(raw).problems.join("\n")).to include(message)
    end
  end

  it "reports duplicate ids" do
    reports = described_class.new([Evals::Case.new(good.deep_stringify_keys), Evals::Case.new(good.deep_stringify_keys)]).run
    expect(reports.first.problems).to include("duplicate id t-fleet")
  end

  it "leaves the database as it was" do
    create(:asset, tag: "X-1")
    expect { described_class.new(Evals.load_cases.first(5)).run }.not_to(change { [Asset.pluck(:tag), Checkout.count, MaintenanceTask.count] })
  end
end
