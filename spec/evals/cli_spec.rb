require "rails_helper"

RSpec.describe Evals::Cli do
  it "runs offline by default without a key and exits 0" do
    out = StringIO.new
    code = described_class.run(%w[--no-write --tag refusal], out: out, err: StringIO.new, env: {})
    expect(code).to eq(0)
    expect(out.string).to include("| refusal | 4 | 4 | 100% |", "OFFLINE EVALS PASSED")
  end

  it "refuses --live without a key" do
    err = StringIO.new
    expect(described_class.run(%w[--live], out: StringIO.new, err: err, env: {})).to eq(2)
    expect(err.string).to include("ANTHROPIC_API_KEY")
  end

  it "writes dated results and a summary table" do
    Dir.mktmpdir do |dir|
      code = described_class.run(["--only", "fleet-summary", "--out", dir], out: StringIO.new, err: StringIO.new, env: {})
      expect(code).to eq(0)
      json = JSON.parse(File.read(File.join(dir, "#{Date.current.iso8601}.offline.json")))
      expect(json).to include("mode" => "offline", "as_of" => "2026-11-05T10:00:00Z")
      expect(json["summary"]).to include("cases" => 1, "passed" => 1, "oracle_passed" => 1)
      expect(File.read(File.join(dir, "#{Date.current.iso8601}.offline.md"))).to include("| read | 1 | 1 | 100% |")
    end
  end
end
