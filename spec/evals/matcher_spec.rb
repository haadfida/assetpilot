require "rails_helper"

RSpec.describe Evals::Matcher do
  def m(spec) = described_class.build(spec)

  it "treats a bare literal as exact" do
    expect(m("laptop").match?("laptop")).to be(true)
    expect(m("laptop").match?("Laptop")).to be(false)
    expect(m(true).match?(true)).to be(true)
    expect(m(30).match?(30)).to be(true)
    expect(m({ "a" => 1 }).match?({ "a" => 1 })).to be(true) # an object that is not a matcher is a literal
  end

  it "matches regexes on strings only, with flags" do
    expect(m({ "regex" => "^db-server$", "flags" => "i" }).match?("DB-Server")).to be(true)
    expect(m({ "regex" => "^db-server$" }).match?("DB-Server")).to be(false)
    expect(m({ "regex" => "1" }).match?(1)).to be(false)
  end

  it "matches subsets of arrays and objects" do
    expect(m({ "subset" => %w[AP-1] }).match?(%w[AP-1 AP-2])).to be(true)
    expect(m({ "subset" => %w[AP-3] }).match?(%w[AP-1 AP-2])).to be(false)
    expect(m({ "subset" => { "kind" => "inspection", "due_on" => { "regex" => "^2026-" } } })
             .match?({ "kind" => "inspection", "due_on" => "2026-11-12", "extra" => 1 })).to be(true)
  end

  it "matches sets regardless of order but not with extra or missing elements" do
    expect(m({ "set" => %w[b a] }).match?(%w[a b])).to be(true)
    expect(m({ "set" => %w[a b] }).match?(%w[a b c])).to be(false)
    expect(m({ "set" => %w[a b] }).match?(%w[a])).to be(false)
  end

  it "matches absent arguments" do
    expect(m({ "absent" => true }).match?(nil, present: false)).to be(true)
    expect(m({ "absent" => true }).match?(nil, present: true)).to be(false)
    expect(m("x").match?(nil, present: false)).to be(false)
  end

  it "rejects malformed matchers" do
    expect { m({ "regex" => "(" }) }.to raise_error(described_class::Invalid, /does not compile/)
    expect { m({ "regex" => "a", "flags" => "z" }) }.to raise_error(described_class::Invalid, /flags/)
    expect { m({ "set" => "a" }) }.to raise_error(described_class::Invalid)
    expect { m({ "absent" => false }) }.to raise_error(described_class::Invalid)
  end
end
