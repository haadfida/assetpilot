module SseHelpers
  # Parses a text/event-stream body into [[event, data_hash], ...].
  def parse_sse(body)
    body.split("\n\n").filter_map do |frame|
      event = frame[/^event: (.+)$/, 1]
      data = frame[/^data: (.+)$/, 1]
      [event, JSON.parse(data)] if event && data
    end
  end

  # Event names with consecutive duplicates collapsed (text deltas -> one "text").
  def event_sequence(events) = events.map(&:first).chunk_while { |a, b| a == b }.map(&:first)
end

RSpec.configure { |c| c.include SseHelpers }
