module Api
  # POST /api/agent/runs            -> creates a run (live with a key, otherwise a replay of a known prompt)
  # GET  /api/agent/runs/:id/stream -> executes it (first attach) and streams SSE; re-streams finished runs
  # GET  /api/agent/runs/:id        -> the run and its ordered steps
  # GET  /api/agent/replays         -> prompts that can be replayed without a key
  #
  # BYOK: the Anthropic key comes only from the `x-anthropic-key` request header (ANTHROPIC_API_KEY is a
  # development-only fallback). It lives in a local variable for the request, is used to build the SDK
  # client, and is never stored, logged or rendered. Live runs execute on the stream request, so that
  # request carries the key too; nothing has to hold it in between.
  class AgentRunsController < BaseController
    include ActionController::Live

    KEY_HEADER = "x-anthropic-key".freeze
    # Process-local so limits work even where the app cache is a null store. Keys are SHA-256 digests.
    RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

    rate_limit to: Integer(ENV.fetch("AGENT_RATE_LIMIT", 10)), within: 1.minute, only: :create, name: "create",
               by: :rate_limit_identity, store: RATE_LIMIT_STORE, with: :render_rate_limited
    rate_limit to: Integer(ENV.fetch("AGENT_STREAM_RATE_LIMIT", 30)), within: 1.minute, only: :stream, name: "stream",
               by: :rate_limit_identity, store: RATE_LIMIT_STORE, with: :render_rate_limited

    def create
      prompt = params.require(:prompt).to_s.strip
      key = api_key
      replay = nil
      if key && params[:mode] != "replay"
        mode = "live"
      else
        mode = "replay"
        replay = params[:replay].present? ? ::Agent::Replays.find(params[:replay]) : ::Agent::Replays.find_by_prompt(prompt)
        unless replay
          return render json: { error: "unknown_replay",
                                message: "No API key was sent (header #{KEY_HEADER}), so only recorded prompts can be replayed.",
                                replays: ::Agent::Replays.catalog }, status: :unprocessable_content
        end
      end

      run = AgentRun.create!(prompt: replay ? replay.prompt : prompt, mode: mode,
                             model: replay ? replay.model : ::Agent::Config.current.model,
                             replay_slug: replay&.slug, recorded: replay&.recorded)
      render json: { data: run.summary.merge(stream_url: stream_api_agent_run_path(run)) }, status: :created
    rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid => e
      render json: { error: "bad_request", message: e.message }, status: :bad_request
    end

    def show
      run = AgentRun.find(params[:id])
      render json: { data: run.summary.merge(steps: run.steps.map { |s| s.as_event.merge(kind: s.kind, elapsed_ms: s.elapsed_ms) }) }
    end

    def replays
      render json: { data: ::Agent::Replays.catalog }
    end

    def stream
      run = AgentRun.find(params[:id])
      key = api_key
      if run.live? && !run.finished? && key.nil?
        return render json: { error: "missing_api_key", message: "Live runs need the #{KEY_HEADER} header on the stream request." },
                      status: :unauthorized
      end

      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["X-Accel-Buffering"] = "no"
      response.headers["Last-Modified"] = Time.now.httpdate # keeps Rack::ETag from buffering the stream

      recorder = ::Agent::Recorder.new(run, emit: ->(event, data) { write_event(event, data) })
      if run.finished?
        recorder.emit_stored
      elsif run.claim!
        execute(run, recorder, key)
      else
        write_event(:error, code: "already_streaming", message: "This run is already being streamed.")
      end
    rescue ActiveRecord::RecordNotFound
      raise
    rescue StandardError => e
      Rails.logger.error("[agent] stream #{params[:id]} failed: #{e.class}")
      write_event(:error, code: "internal_error", message: "Streaming failed") rescue nil
    ensure
      response.stream.close
    end

    private

    def execute(run, recorder, key)
      if run.replay?
        replay = ::Agent::Replays.find(run.replay_slug)
        return recorder.tap { |r| r.error(code: "unknown_replay", message: "Replay #{run.replay_slug} is missing") }
                       .finish!(status: "failed", error_code: "unknown_replay") unless replay

        ::Agent::Replayer.new(run: run, replay: replay, recorder: recorder, speed: replay_speed).call
      else
        ::Agent::Runner.new(run: run, client: self.class.client_factory.call(key), recorder: recorder).call(api_key: key)
      end
    end

    def write_event(event, data)
      response.stream.write("event: #{event}\ndata: #{JSON.generate(data.as_json)}\n\n")
    end

    def replay_speed
      params[:speed].presence&.to_f || ::Agent::Config.current.replay_speed
    end

    def api_key
      key = request.headers[KEY_HEADER].presence
      key ||= ENV["ANTHROPIC_API_KEY"].presence if Rails.env.development?
      key = key&.strip
      key if key.present? && key.length <= 256 && key.match?(/\A[\x21-\x7e]+\z/)
    end

    def rate_limit_identity
      key = api_key
      key ? "key:#{Digest::SHA256.hexdigest(key)}" : "ip:#{request.remote_ip}"
    end

    def render_rate_limited
      render json: { error: "rate_limited", message: "Too many agent requests; try again in a minute." }, status: :too_many_requests
    end

    class << self
      # Swappable in specs. Builds the SDK client for one request; the key is not retained.
      attr_writer :client_factory

      def client_factory = @client_factory || ->(key) { ::Agent.build_client(key) }
    end
  end
end
