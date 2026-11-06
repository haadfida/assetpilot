require "rails_helper"

# Self-test of the deterministic grader: transcripts that must pass and transcripts that must fail, each
# graded against a real case from evals/cases.jsonl. Tool calls in a fixture are executed for real inside
# the eval sandbox (seeded, clock frozen) unless the call carries an "output", so db assertions are real too.
RSpec.describe Evals::Grader do
  cases = Evals.load_cases.index_by(&:id)
  fixtures = Rails.root.glob("spec/fixtures/evals/transcripts/*.json").sort.map { |p| [p.basename(".json").to_s, JSON.parse(p.read)] }

  # One seeded sandbox for all fixtures (it rolls itself back), one savepoint per fixture.
  before(:context) do
    @results = Evals::Sandbox.run do
      fixtures.to_h do |name, fixture|
        kase = cases.fetch(fixture["case"])
        result = Evals::Sandbox.isolated do
          before = Evals::DbState.snapshot
          transcript = Evals::Transcript.execute(fixture["calls"], answer: fixture["final_text"], status: fixture.fetch("status", "succeeded"))
          described_class.grade(kase, transcript, before.evaluate(kase.db_assertions))
        end
        [name, result]
      end
    end
  end

  it "has passing and failing fixtures" do
    expect(fixtures.map(&:first)).to include(start_with("pass-"), start_with("fail-"))
    expect(fixtures.map { |_, f| f["expect"]["pass"] }.uniq).to contain_exactly(true, false)
  end

  fixtures.each do |name, fixture|
    it "#{fixture['expect']['pass'] ? 'passes' : 'fails'} #{name} (case #{fixture['case']})" do
      result = @results.fetch(name)
      expect(result.pass).to be(fixture["expect"]["pass"]), -> { "#{name}: #{result.failures.inspect}" }
      failed = result.dimensions.reject { |_, ok| ok }.keys
      expect(failed).to match_array(fixture["expect"].fetch("failed", [])), -> { "#{name}: #{result.failures.inspect}" }
    end
  end

  it "explains failures in words" do
    result = @results.fetch("fail-wrong-node")
    expect(result.failures.first).to include("impact_analysis(node /^(DB-Server|AP-00502)$/i", "Core-Switch-DC1")
  end

  it "rejects an empty transcript for every case" do
    Evals::Sandbox.run do
      cases.each_value do |kase|
        r = Evals::Sandbox.isolated { described_class.grade(kase, Evals::Transcript.null, Evals::DbState.snapshot.evaluate(kase.db_assertions)) }
        expect(r.pass).to be(false), "#{kase.id} passes an empty transcript"
      end
    end
  end
end
