# One agent run: a prompt, executed live against the Claude API or replayed from db/replays.
# The API key is never stored here (or anywhere); see Api::AgentRunsController.
class AgentRun < ApplicationRecord
  MODES = %w[live replay].freeze
  STATUSES = %w[queued running succeeded failed refused max_iterations].freeze
  FINISHED = STATUSES - %w[queued running]

  has_many :steps, -> { order(:position) }, class_name: "AgentStep", dependent: :delete_all, inverse_of: :agent_run

  validates :prompt, presence: true, length: { maximum: 4000 }
  validates :model, presence: true
  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :replay_slug, presence: true, if: :replay?

  def live? = mode == "live"
  def replay? = mode == "replay"
  def finished? = FINISHED.include?(status)

  # Atomically moves queued -> running so only one stream executes a run.
  def claim!
    claimed = self.class.where(id: id, status: "queued").update_all(status: "running", started_at: Time.current, updated_at: Time.current)
    reload
    claimed == 1
  end

  def usage
    { input_tokens:, output_tokens:, cache_read_input_tokens:, cache_creation_input_tokens: }
  end

  def summary
    { id:, prompt:, model:, mode:, status:, recorded:, replay_slug:, iterations:, stop_reason:, usage:,
      error: error_code && { code: error_code, message: error_message },
      started_at:, finished_at:, duration_ms:, created_at: }
  end
end
