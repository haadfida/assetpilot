module Agent
  # Recorded runs in db/replays/*.json, matched by prompt. Used when a request has no API key.
  module Replays
    DIR = Rails.root.join("db/replays")

    Replay = Struct.new(:data) do
      %w[slug prompt model recorded status stop_reason iterations duration_ms steps as_of].each do |k|
        define_method(k) { data[k] }
      end

      def prompts = [prompt, *data.fetch("aliases", [])]

      def usage = data.fetch("usage", {}).slice(*%w[input_tokens output_tokens cache_read_input_tokens cache_creation_input_tokens]).symbolize_keys
    end

    module_function

    def all
      return load_all unless Rails.env.production?

      @all ||= load_all
    end

    def load_all
      Dir[DIR.join("*.json")].sort.map { |f| Replay.new(JSON.parse(File.read(f))) }
    end

    def find(slug) = all.find { |r| r.slug == slug.to_s }

    def find_by_prompt(prompt)
      key = normalize(prompt)
      all.find { |r| r.prompts.any? { |p| normalize(p) == key } }
    end

    def normalize(text) = text.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip

    def catalog = all.map { |r| { slug: r.slug, prompt: r.prompt, recorded: r.recorded } }
  end
end
