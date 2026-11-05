# Builds Messages API streaming bodies (text/event-stream) for WebMock, so specs exercise the real SDK.
module AnthropicSse
  module_function

  def body(blocks, stop_reason:, input_tokens: 500, output_tokens: 40)
    events = [["message_start", { type: "message_start", message: {
      id: "msg_#{SecureRandom.hex(6)}", type: "message", role: "assistant", model: "claude-opus-5-5", content: [],
      stop_reason: nil, stop_sequence: nil, usage: { input_tokens: input_tokens, output_tokens: 1 }
    } }]]
    blocks.each_with_index do |b, i|
      case b[:type]
      when "thinking"
        events << start(i, type: "thinking", thinking: "", signature: "")
        events << delta(i, type: "thinking_delta", thinking: b[:thinking])
        events << delta(i, type: "signature_delta", signature: b[:signature])
      when "text"
        events << start(i, type: "text", text: "")
        b[:text].scan(/.{1,10}/m).each { |c| events << delta(i, type: "text_delta", text: c) }
      when "tool_use"
        events << start(i, type: "tool_use", id: b[:id], name: b[:name], input: {})
        json = b[:input].to_json
        [json[0, json.size / 2], json[json.size / 2..]].each { |part| events << delta(i, type: "input_json_delta", partial_json: part) }
      end
      events << ["content_block_stop", { type: "content_block_stop", index: i }]
    end
    events << ["message_delta", { type: "message_delta", delta: { stop_reason: stop_reason, stop_sequence: nil },
                                  usage: { output_tokens: output_tokens } }]
    events << ["message_stop", { type: "message_stop" }]
    events.map { |name, data| "event: #{name}\ndata: #{data.to_json}\n\n" }.join
  end

  def start(i, block) = ["content_block_start", { type: "content_block_start", index: i, content_block: block }]
  def delta(i, d) = ["content_block_delta", { type: "content_block_delta", index: i, delta: d }]

  def response(blocks, **opts)
    { status: 200, headers: { "Content-Type" => "text/event-stream" }, body: body(blocks, **opts) }
  end
end
