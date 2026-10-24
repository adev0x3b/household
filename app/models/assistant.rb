# frozen_string_literal: true

# The assistant's configuration. It runs on Ollama unless told otherwise, so
# the household's data stays on its own server.
#
# Each value is read from the first of these that sets it:
#   1. an eval run's own choice: EVAL_PROVIDER, EVAL_MODEL, EVAL_TEMPERATURE
#   2. the settings an admin saved on /assistant/settings (Assistant::Setting),
#      which once saved hold everything but the API keys
#   3. the environment:
#      ASSISTANT_PROVIDER  ollama (the default), anthropic or openai
#      ASSISTANT_MODEL     else OLLAMA_MODEL, else qwen3:8b
#      OLLAMA_BASE_URL     the server, without /v1
#      ANTHROPIC_API_KEY, OPENAI_API_KEY  also read when no key was saved
#      ASSISTANT_THINKING  the reasoning effort sent to the provider; unset
#                          leaves the model's own. Small models answer faster
#                          without thinking but misfile fields and claim saves
#                          that didn't happen, so it is best left on.
#      ASSISTANT_MAX_OUTPUT_TOKENS  per model step, which stops a model that
#                          would otherwise think without end
#      ASSISTANT_CONTEXT_TOKENS  the model's context window as served. Ollama
#                          cuts a longer prompt silently, so a step close to it
#                          is logged as a warning.
#      ASSISTANT_TEMPERATURE  "none" leaves it out, for models that refuse it
#
# ASSISTANT_PROMPT_EXAMPLES=0 leaves the worked examples out of the
# instructions, to compare both in an eval.
module Assistant
  DEFAULT_MAX_OUTPUT_TOKENS = 4096
  DEFAULT_OLLAMA_URL = "http://localhost:11434"

  def self.table_name_prefix
    "assistant_"
  end

  def self.saved = Assistant::Setting.saved

  # A cloud provider answers the chats, health data included, so
  # the chat and the settings page say so.
  def self.cloud? = provider != :ollama

  def self.provider
    (ENV["EVAL_PROVIDER"].presence || saved&.provider || ENV["ASSISTANT_PROVIDER"].presence || "ollama").to_sym
  end

  def self.model
    ENV["EVAL_MODEL"].presence || saved&.model || ENV["ASSISTANT_MODEL"].presence ||
      (provider == :ollama && ENV["OLLAMA_MODEL"].presence) || "qwen3:8b"
  end

  # nil leaves the provider's default.
  def self.thinking_effort
    saved ? saved.thinking_effort : ENV["ASSISTANT_THINKING"].presence
  end

  def self.max_output_tokens
    (saved ? saved.max_output_tokens : ENV["ASSISTANT_MAX_OUTPUT_TOKENS"].presence&.to_i) || DEFAULT_MAX_OUTPUT_TOKENS
  end

  # nil: don't send one.
  def self.temperature
    value = ENV["EVAL_TEMPERATURE"].presence || (saved ? saved.temperature&.to_s : ENV["ASSISTANT_TEMPERATURE"].presence || "0.2")
    value.nil? || value == "none" ? nil : value.to_f
  end

  def self.prompt_examples? = ENV["ASSISTANT_PROMPT_EXAMPLES"].presence != "0"

  def self.context_tokens
    saved ? saved.context_tokens : ENV["ASSISTANT_CONTEXT_TOKENS"].presence&.to_i
  end

  # A step this big may have been cut off by the provider.
  def self.near_context_limit?(input_tokens)
    context_tokens.present? && input_tokens.to_i >= context_tokens * 0.9
  end

  # Ollama's server, without the /v1 RubyLLM talks to.
  def self.ollama_url
    (saved&.ollama_url || ENV["OLLAMA_BASE_URL"].presence || DEFAULT_OLLAMA_URL).delete_suffix("/v1").chomp("/")
  end

  # A provider's API key: the saved one, else the environment's.
  def self.api_key(provider)
    saved&.api_key(provider).presence || ENV["#{provider.to_s.upcase}_API_KEY"].presence
  end

  # Where a provider's key comes from, for the settings page: :saved, :env or nil.
  def self.key_source(provider)
    if saved&.api_key(provider).present? then :saved
    elsif ENV["#{provider.to_s.upcase}_API_KEY"].present? then :env
    end
  end

  # How to reach the providers as configured now. A chat takes it before
  # its RubyLLM chat is built, because a provider without its key raises
  # there.
  def self.llm_context
    Current.llm_context ||= RubyLLM.context do |config|
      config.ollama_api_base = "#{ollama_url}/v1"
      config.anthropic_api_key = api_key(:anthropic)
      config.openai_api_key = api_key(:openai)
    end
  end
end
