# frozen_string_literal: true

require "test_helper"

# Preflight asks Assistant::Connection with the configured credentials
# (saved settings, else .env).
class AssistantEval::PreflightTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  isolate_env "OLLAMA_BASE_URL", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"

  def answering(response, &) = swapping(Assistant::Connection, :perform, ->(_request, **) { response }, &)

  test "an Ollama server that has the model passes, with or without the :latest tag" do
    ENV["OLLAMA_BASE_URL"] = "http://ollama.local:11434/v1"
    tags = Response.new("200", { models: [ { name: "qwen3-8b-household:latest" }, { name: "qwen3:8b" } ] }.to_json)

    answering(tags) do
      assert AssistantEval::Preflight.check!(provider: "ollama", model: "qwen3-8b-household")
      assert AssistantEval::Preflight.check!(provider: "ollama", model: "qwen3:8b")
      error = assert_raises(AssistantEval::Preflight::Unavailable) { AssistantEval::Preflight.check!(provider: "ollama", model: "llama9") }
      assert_match "doesn't have llama9", error.message
    end
  end

  test "an Ollama server that doesn't answer is unreachable" do
    ENV["OLLAMA_BASE_URL"] = "http://ollama.local:11434"
    swapping(Assistant::Connection, :perform, ->(_request, **) { raise Assistant::Connection::Error, "the Ollama server isn't answering (OpenTimeout)" }) do
      error = assert_raises(AssistantEval::Preflight::Unavailable) { AssistantEval::Preflight.check!(provider: "ollama", model: "qwen3:8b") }
      assert_match "isn't answering", error.message
    end
  end

  test "Anthropic: a known model passes, an unknown one doesn't, a missing key is said plainly" do
    ENV["ANTHROPIC_API_KEY"] = "test-key"
    answering(Response.new("200", "{}")) { assert AssistantEval::Preflight.check!(provider: "anthropic", model: "claude-haiku-4-5") }
    answering(Response.new("404", "{}")) do
      error = assert_raises(AssistantEval::Preflight::Unavailable) { AssistantEval::Preflight.check!(provider: "anthropic", model: "claude-nope") }
      assert_match "no model claude-nope", error.message
    end

    ENV.delete("ANTHROPIC_API_KEY")
    error = assert_raises(AssistantEval::Preflight::Unavailable) { AssistantEval::Preflight.check!(provider: "anthropic", model: "claude-haiku-4-5") }
    assert_match "no Anthropic API key", error.message
  end

  test "OpenAI: the key saved on the settings page is the one sent, and a refused key says so" do
    Assistant::Setting.create!(provider: "openai", model: "gpt-5.6-luna", openai_api_key: "sk-saved")
    sent = nil
    swapping(Assistant::Connection, :perform, ->(request, **) { sent = request; Response.new("200", "{}") }) do
      assert AssistantEval::Preflight.check!(provider: "openai", model: "gpt-5.6-luna")
    end
    assert_equal "Bearer sk-saved", sent["Authorization"]

    answering(Response.new("401", "{}")) do
      error = assert_raises(AssistantEval::Preflight::Unavailable) { AssistantEval::Preflight.check!(provider: "openai", model: "gpt-5.6-luna") }
      assert_match "refused the API key", error.message
    end
  end
end
