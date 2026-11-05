require "rails_helper"

RSpec.describe Tools::Base do
  it "sends strict schemas without the keywords strict tool use rejects, but enforces them locally" do
    defn = Tools::SearchAssets.definition
    expect(defn).to include(strict: true, eager_input_streaming: true)
    expect(defn[:input_schema]["additionalProperties"]).to be(false)
    expect(defn[:input_schema].to_json).not_to match(/"(minimum|maximum|minLength|maxItems)"/)
    expect(Tools::SearchAssets.input_schema.dig("properties", "limit", "maximum")).to eq(50)
  end

  it "marks every object schema additionalProperties: false" do
    Tools::Registry::TOOLS.each do |tool|
      expect(tool.input_schema).to include("type" => "object", "additionalProperties" => false)
      expect(tool.description).to be_present
    end
  end

  it "rejects non-object input (e.g. an unparseable eager-streamed buffer) without raising" do
    expect_error(Tools::GetAsset.call('{"asset": "AP-'), "invalid_input")
  end

  it "rejects unknown properties and wrong types with pointers" do
    err = expect_error(Tools::GetAsset.call(asset: 42, extra: true), "invalid_input")
    pointers = err.dig("details", "problems").map { |p| p["pointer"] }
    expect(pointers).to include("/asset")
  end

  it "turns unexpected exceptions into internal_error" do
    allow(Asset).to receive(:find_by).and_raise(RuntimeError, "db exploded")
    err = expect_error(Tools::GetAsset.call(asset: "X-1"), "internal_error")
    expect(err["message"]).not_to include("db exploded")
  end

  it "reports unknown tools from the registry" do
    expect_error(Tools::Registry.call("drop_tables", {}), "unknown_tool")
  end
end
