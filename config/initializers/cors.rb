# CORS for the React frontend (frontend/) when it is served from a different origin than the API.
#
# CORS_ORIGINS is a comma-separated list of allowed origins, e.g.
#   CORS_ORIGINS=https://assetpilot.example.com,http://localhost:4173
# In development it defaults to the Vite dev and preview servers. In development the Vite dev server
# proxies /api, so CORS is only needed for `vite preview` or a separately hosted build.
# Nothing is allowed when CORS_ORIGINS is unset outside development.
origins = ENV.fetch("CORS_ORIGINS") { Rails.env.development? ? "http://localhost:5173,http://localhost:4173" : "" }
              .split(",").map(&:strip).reject(&:empty?)

if origins.any?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins(*origins)

      resource "/api/*",
               headers: %w[content-type x-anthropic-key],
               methods: %i[get post options head],
               max_age: 600
    end
  end
end
