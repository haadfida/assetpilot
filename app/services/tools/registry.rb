module Tools
  # The agent's tool surface. The order is fixed: the tools array is part of the cached prompt prefix.
  module Registry
    TOOLS = [SearchAssets, GetAsset, CheckoutAsset, CheckinAsset, ScheduleMaintenance, ImpactAnalysis, SummarizeFleet].freeze
    BY_NAME = TOOLS.index_by(&:tool_name).freeze

    module_function

    def definitions = TOOLS.map(&:definition)

    def names = BY_NAME.keys

    def fetch(name) = BY_NAME[name.to_s]

    # Runs a tool by name. Unknown names come back as a structured error, never an exception.
    def call(name, input)
      tool = fetch(name)
      return { "ok" => false, "error" => { "code" => "unknown_tool", "message" => "No tool named #{name.inspect}", "details" => {} } } unless tool

      tool.call(input)
    end
  end
end
