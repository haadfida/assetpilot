source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.4", ">= 8.1.4.1"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"
# Use Redis adapter to run Action Cable in production
# gem "redis", ">= 4.0.1"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]

# Claude API (official Anthropic Ruby SDK) for the agent loop
gem "anthropic", "~> 2.5"
# Validates tool inputs against the same JSON schemas sent to the model
gem "json_schemer", "~> 2.5"
# Official MCP Ruby SDK: exposes the same tools to Claude Code / Claude Desktop
gem "mcp", "~> 1.9"

# Deterministic synthetic seed data (lib/seed_data.rb). Needed in production too: the deployed demo is
# seeded from it, and lib/ is eager-loaded there.
gem "faker"

# CORS for the React frontend when it is served from another origin (CORS_ORIGINS)
gem "rack-cors", "~> 3.0"

group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :test do
  gem "webmock"
end
