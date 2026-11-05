# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, "x-anthropic-key", :x_anthropic_key, :anthropic_key, :api_key, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# The BYOK Anthropic key travels in the x-anthropic-key header. Rails does not log headers, and the key is
# never stored; the entries above also filter it if a client sends it as a parameter by mistake.
