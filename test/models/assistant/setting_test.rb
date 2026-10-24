# frozen_string_literal: true

require "test_helper"

# The assistant's configuration: eval override, then the saved settings,
# then the environment. Keys are encrypted and never come back to a form.
class Assistant::SettingTest < ActiveSupport::TestCase
  isolate_env "ASSISTANT_PROVIDER", "ASSISTANT_MODEL", "OLLAMA_MODEL", "OLLAMA_BASE_URL", "ASSISTANT_TEMPERATURE",
              "ASSISTANT_CONTEXT_TOKENS", "ASSISTANT_THINKING", "ASSISTANT_MAX_OUTPUT_TOKENS", "ANTHROPIC_API_KEY",
              "OPENAI_API_KEY", "EVAL_PROVIDER", "EVAL_MODEL", "EVAL_TEMPERATURE"

  def saved(**attributes)
    Assistant::Setting.create!(provider: "ollama", model: "qwen3-8b-household", ollama_url: "http://ollama.local:11434", **attributes)
  end

  test "until an admin saves, the environment decides" do
    ENV["OLLAMA_BASE_URL"] = "http://ollama.local:11434/v1"
    ENV["OLLAMA_MODEL"] = "qwen3-8b-household"
    ENV["ASSISTANT_CONTEXT_TOKENS"] = "12288"

    assert_equal :ollama, Assistant.provider
    assert_equal "qwen3-8b-household", Assistant.model
    assert_equal "http://ollama.local:11434", Assistant.ollama_url, "without the /v1 RubyLLM adds"
    assert_equal 12_288, Assistant.context_tokens
    assert_in_delta 0.2, Assistant.temperature
    assert_equal Assistant::DEFAULT_MAX_OUTPUT_TOKENS, Assistant.max_output_tokens
  end

  test "once saved, the row owns the configuration — a blank field is the provider's default, not the environment's" do
    ENV["ASSISTANT_PROVIDER"] = "ollama"
    ENV["ASSISTANT_CONTEXT_TOKENS"] = "12288"
    ENV["ASSISTANT_TEMPERATURE"] = "0.5"
    ENV["ANTHROPIC_API_KEY"] = "sk-env"
    saved(provider: "anthropic", model: "claude-haiku-4-5-20251001", temperature: nil, context_tokens: nil, thinking_effort: "low")

    assert_equal :anthropic, Assistant.provider
    assert_equal "claude-haiku-4-5-20251001", Assistant.model
    assert_nil Assistant.temperature, "blank: none is sent"
    assert_nil Assistant.context_tokens
    assert_equal "low", Assistant.thinking_effort
    assert_equal "sk-env", Assistant.api_key(:anthropic), "a key never saved still comes from the environment"
    assert_equal :env, Assistant.key_source(:anthropic)
  end

  test "an eval process's override wins over the saved settings" do
    saved
    ENV["EVAL_PROVIDER"] = "anthropic"
    ENV["EVAL_MODEL"] = "claude-haiku-4-5-20251001"
    ENV["EVAL_TEMPERATURE"] = "none"

    assert_equal :anthropic, Assistant.provider
    assert_equal "claude-haiku-4-5-20251001", Assistant.model
    assert_nil Assistant.temperature
  end

  test "API keys are encrypted at rest, and a blank field keeps the saved key" do
    setting = saved(anthropic_api_key: "sk-ant-secret-1234")
    stored = Assistant::Setting.connection.select_value("SELECT anthropic_api_key FROM assistant_settings WHERE id = #{setting.id}")

    assert_not_includes stored, "sk-ant-secret-1234"
    assert_equal "sk-ant-secret-1234", setting.reload.anthropic_api_key

    setting.assign_settings("model" => "qwen3:8b", "anthropic_api_key" => "", "openai_api_key" => "sk-new").save!
    assert_equal "sk-ant-secret-1234", setting.reload.anthropic_api_key
    assert_equal "sk-new", setting.openai_api_key
    assert_equal :saved, Assistant.key_source(:anthropic)
  end

  test "the context every chat gets carries the configured server and keys" do
    saved(ollama_url: "http://ollama.local:11434/", openai_api_key: "sk-openai")
    config = Assistant.llm_context.config

    assert_equal "http://ollama.local:11434/v1", config.ollama_api_base
    assert_equal "sk-openai", config.openai_api_key
  end

  test "saving drops the memo, so the next read sees the change" do
    setting = saved
    assert_equal "qwen3-8b-household", Assistant.model

    setting.update!(model: "qwen3:8b")
    assert_equal "qwen3:8b", Assistant.model
  end

  test "validations: a known provider, a model, a server for Ollama, a key for the keyed providers" do
    setting = Assistant::Setting.new(provider: "shell", model: "qwen3; rm -rf /", ollama_url: "ftp://ollama.local")
    assert_not setting.valid?
    assert setting.errors.of_kind?(:provider, :inclusion)
    assert setting.errors.of_kind?(:model, :invalid)
    assert setting.errors.of_kind?(:ollama_url, :invalid)

    keyed = Assistant::Setting.new(provider: "openai", model: "gpt-5.6-luna", temperature: 3)
    assert_not keyed.valid?
    assert keyed.errors.of_kind?(:openai_api_key, :blank)
    assert keyed.errors.of_kind?(:temperature, :less_than_or_equal_to)
  end

  test "an existing chat moves to the model configured now on its next reply" do
    chat = assistant_chat(profiles(:alice))
    saved(model: "qwen3-8b-household")

    chat.reload.follow_settings!
    assert_equal "qwen3-8b-household", chat.reload.model_id
    assert_equal "ollama", chat.provider.to_s
  end

  test "the agent applies the configured tuning to the reply's chat" do
    chat = assistant_chat(profiles(:alice))
    saved(temperature: 0.3, max_output_tokens: 2048, thinking_effort: "low")

    llm = Assistant::BookkeeperAgent.for(chat).to_llm
    assert_in_delta 0.3, llm.temperature
    assert_equal 2048, llm.max_output_tokens
    assert_equal "http://ollama.local:11434/v1", llm.context.config.ollama_api_base
  end
end
