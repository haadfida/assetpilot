module Agent
  # Model and request parameters, per the claude-api skill:
  # - claude-opus-5-5, the skill's default model.
  # - Adaptive thinking (thinking can't be disabled on Opus 5.5; effort is the control). display: "updates"
  #   (beta thinking-display-updates-2026-08-18) returns the model's between-tool-call progress notes as
  #   text, which we stream as `progress` events; reasoning itself stays hidden.
  # - effort set explicitly: Opus 5.5 defaults to "medium" and the skill says to set it; medium is its
  #   recommended starting point for multi-step tool use.
  # - Streaming with max_tokens 64000 (skill default for streamed requests; thinking counts toward it).
  # - fallbacks: "default" (beta server-side-fallback-2026-07-01), on by default for Opus 5.5 code so a
  #   classifier false positive is retried server-side instead of failing the run.
  # - tool_choice auto: forced tool_choice returns 400 on Opus 5.5. Tools are strict + eager_input_streaming.
  # - Top-level cache_control: tools + system are a stable prefix (the date goes in the user turn).
  Config = Struct.new(:model, :max_tokens, :effort, :max_tool_iterations, :replay_speed, keyword_init: true) do
    def self.current
      new(model: ENV.fetch("AGENT_MODEL", "claude-opus-5-5"),
          max_tokens: Integer(ENV.fetch("AGENT_MAX_TOKENS", 64_000)),
          effort: ENV.fetch("AGENT_EFFORT", "medium"),
          max_tool_iterations: Integer(ENV.fetch("AGENT_MAX_TOOL_ITERATIONS", 8)),
          replay_speed: Float(ENV.fetch("AGENT_REPLAY_SPEED", 1.0)))
    end

    BETAS = %w[server-side-fallback-2026-07-01 thinking-display-updates-2026-08-18].freeze

    def request(messages)
      {
        model: model, max_tokens: max_tokens,
        system_: SYSTEM_PROMPT, messages: messages,
        tools: Tools::Registry.definitions, tool_choice: { type: "auto" },
        thinking: { type: "adaptive", display: "updates" },
        output_config: { effort: effort },
        fallbacks: :default,
        cache_control: { type: "ephemeral" },
        betas: BETAS
      }
    end
  end
end
