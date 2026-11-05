# MCP (Model Context Protocol) surface for AssetPilot. It wraps the agent's tools, it does not
# reimplement them: the list of tools, their names, descriptions, JSON schemas and the mutating flag all
# come from Tools::Registry, so the agent and MCP cannot drift. Every call goes through Tools::Base#execute,
# which validates input against the schema and returns {ok, data} / {ok: false, error}.
module AssetpilotMcp
  SUMMARY_URI = "inventory://summary".freeze

  module_function

  # Builds an MCP::Server. With allow_writes: false the mutating tools are not exposed at all and are
  # refused if called anyway.
  def build_server(allow_writes: true)
    tools = Tools::Registry::TOOLS.select { |t| allow_writes || !t.mutating? }.map { |t| tool_class(t, allow_writes) }
    MCP::Server.new(
      name: "assetpilot",
      title: "AssetPilot",
      version: "1.0.0",
      instructions: "IT asset inventory. Read tools (search_assets, get_asset, impact_analysis, summarize_fleet) are safe; " \
                    "checkout_asset, checkin_asset and schedule_maintenance change data, so call them only when asked.",
      tools: tools,
      resources: [summary_resource],
      configuration: MCP::Configuration.new(validate_tool_call_arguments: false) # Tools::Base validates, with structured errors
    )
  end

  # An MCP::Tool class for one Tools::Base subclass.
  def tool_class(source, allow_writes)
    Class.new(MCP::Tool) do
      tool_name source.tool_name
      description source.description
      input_schema source.input_schema.deep_symbolize_keys
      annotations(read_only_hint: !source.mutating?, destructive_hint: source.destructive?,
                  idempotent_hint: !source.mutating?, open_world_hint: false)

      define_singleton_method(:call) do |server_context: nil, **args|
        result =
          if source.mutating? && !allow_writes
            { "ok" => false, "error" => { "code" => "read_only", "message" => "This MCP server is read-only; set MCP_ALLOW_WRITES=1 to enable #{source.tool_name}", "details" => {} } }
          else
            source.call(args.deep_stringify_keys)
          end
        MCP::Tool::Response.new([{ type: "text", text: JSON.generate(result) }], error: !result["ok"], structured_content: result)
      end
    end
  end

  def summary_resource
    MCP::Resource.define(uri: SUMMARY_URI, name: "inventory_summary", title: "Inventory summary",
                         description: "Fleet-wide statistics (the summarize_fleet tool with no filter).",
                         mime_type: "application/json") do |server_context: nil|
      [MCP::Resource::TextContents.new(uri: SUMMARY_URI, mime_type: "application/json",
                                       text: JSON.pretty_generate(Tools::SummarizeFleet.call({})))]
    end
  end

  # Rack app for the streamable HTTP transport (mounted at /mcp). Stateless JSON responses, so it works
  # across Puma workers. Read-only unless MCP_ALLOW_WRITES=1; bearer token required if MCP_TOKEN is set.
  class HttpApp
    def initialize(env = ENV)
      @token = env["MCP_TOKEN"].presence
      @allow_writes = env["MCP_ALLOW_WRITES"] == "1"
      @hosts = env["MCP_ALLOWED_HOSTS"].to_s.split(",").map(&:strip).reject(&:empty?)
      @mutex = Mutex.new
    end

    def call(rack_env)
      return unauthorized unless authorized?(rack_env["HTTP_AUTHORIZATION"])

      transport.call(rack_env)
    end

    private

    def authorized?(header)
      return true unless @token

      given = header.to_s[/\ABearer (.+)\z/, 1].to_s
      ActiveSupport::SecurityUtils.secure_compare(given, @token)
    end

    def transport
      @transport || @mutex.synchronize do
        @transport ||= MCP::Server::Transports::StreamableHTTPTransport.new(
          AssetpilotMcp.build_server(allow_writes: @allow_writes).tap { |s| @server = s },
          stateless: true, enable_json_response: true, allowed_hosts: @hosts
        ).tap { |t| @server.transport = t }
      end
    end

    def unauthorized
      [401, { "content-type" => "application/json", "www-authenticate" => 'Bearer realm="assetpilot"' },
       [JSON.generate(error: "unauthorized")]]
    end
  end
end
