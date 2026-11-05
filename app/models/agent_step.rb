# One ordered step of a run. Text and progress deltas are aggregated into one row per content block.
class AgentStep < ApplicationRecord
  KINDS = %w[text progress tool_use tool_result error].freeze

  belongs_to :agent_run, inverse_of: :steps

  validates :kind, inclusion: { in: KINDS }
  validates :position, presence: true, uniqueness: { scope: :agent_run_id }
  validates :tool_use_id, :tool_name, presence: true, if: -> { kind.in?(%w[tool_use tool_result]) }

  def as_event
    case kind
    when "text", "progress" then { step: position, delta: content }
    when "tool_use" then { step: position, id: tool_use_id, name: tool_name, input: input }
    when "tool_result" then { step: position, tool_use_id:, name: tool_name, is_error:, output:, duration_ms: }
    when "error" then { step: position, code: output&.dig("code"), message: content }
    end
  end
end
