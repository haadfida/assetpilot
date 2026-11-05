# A scripted stand-in for Anthropic::Client, shaped like the SDK's beta streaming helper:
# client.beta.messages.stream(**params) -> stream with #each (typed events) and #accumulated_message.
#
#   client = FakeAnthropic.client(
#     FakeAnthropic.turn([{ type: :thinking, thinking: "Checking." },
#                         { type: :tool_use, id: "toolu_1", name: "summarize_fleet", input: {} }], stop_reason: :tool_use),
#     FakeAnthropic.turn([{ type: :text, text: "All good." }])
#   )
#   client.requests # => params of every request, deep-copied
module FakeAnthropic
  Block = Struct.new(:type, :text, :thinking, :signature, :id, :name, :input, :data, keyword_init: true) do
    def to_h = super.compact
  end
  Usage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens, keyword_init: true)
  StopDetails = Struct.new(:category, :explanation, keyword_init: true)
  Message = Struct.new(:content, :stop_reason, :usage, :stop_details, :model, keyword_init: true)
  Event = Struct.new(:type, :text, :thinking, :index, :content_block, keyword_init: true)
  Turn = Struct.new(:blocks, :stop_reason, :usage, :stop_details, :raise_error, keyword_init: true)

  module_function

  def turn(blocks = [], stop_reason: nil, usage: { input_tokens: 100, output_tokens: 20 }, stop_details: nil, raise_error: nil)
    stop_reason ||= blocks.any? { |b| b[:type] == :tool_use } ? :tool_use : :end_turn
    blocks = blocks.map { |b| Block.new(signature: (b[:type] == :thinking ? "sig-#{b[:thinking].to_s.hash.abs}" : nil), **b) }
    Turn.new(blocks: blocks, stop_reason: stop_reason, usage: Usage.new(**usage),
             stop_details: stop_details && StopDetails.new(**stop_details), raise_error: raise_error)
  end

  def client(*turns, repeat_last: false) = Client.new(turns, repeat_last: repeat_last)

  class Client
    attr_reader :requests

    def initialize(turns, repeat_last:)
      @turns = turns
      @repeat_last = repeat_last
      @requests = []
    end

    def beta = self
    def messages = self

    def stream(**params)
      @requests << Marshal.load(Marshal.dump(params.except(:tools))).merge(tools: params[:tools])
      turn = @turns.size > 1 || !@repeat_last ? @turns.shift : @turns.first
      raise "FakeAnthropic: no scripted turn left for request #{@requests.size}" unless turn
      raise turn.raise_error if turn.raise_error

      Stream.new(turn)
    end
  end

  class Stream
    def initialize(turn) = @turn = turn

    def each
      @turn.blocks.each_with_index do |b, i|
        case b.type
        when :text then b.text.scan(/.{1,8}/m).each { |c| yield Event.new(type: :text, text: c) }
        when :thinking then yield Event.new(type: :thinking, thinking: b.thinking) unless b.thinking.to_s.empty?
        end
        yield Event.new(type: :content_block_stop, index: i, content_block: b)
      end
    end

    def accumulated_message
      Message.new(content: @turn.blocks, stop_reason: @turn.stop_reason, usage: @turn.usage,
                  stop_details: @turn.stop_details, model: "claude-opus-5-5")
    end

    def close; end
  end
end
