# frozen_string_literal: true

# RubyLLM's global configuration: the environment's credentials, and the
# timeouts. The assistant itself uses the credentials configured *now*
# (Assistant.llm_context: /assistant/settings, else these same env vars),
# so this is only the fallback for code that builds a chat directly.
# Only the configured provider is ever contacted. A blank is unset: a Compose
# destination passes a key it doesn't have as "".
RubyLLM.configure do |config|
  config.ollama_api_base = "#{(ENV["OLLAMA_BASE_URL"].presence || "http://localhost:11434").chomp("/")}/v1"
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"].presence
  config.openai_api_key = ENV["OPENAI_API_KEY"].presence

  # A local 8B model can take a while per step; the reply runs in a job.
  config.request_timeout = 180
  config.max_retries = 1
  config.logger = Rails.logger
end
