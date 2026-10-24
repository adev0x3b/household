# frozen_string_literal: true

require "test_helper"

# The first setup's Test press: the assistant step's provider, key and model
# are tried before anything is saved, and the key typed lists its models.
# Only the browser that gave the setup code may ask.
class SetupAssistantTestsControllerTest < ActionDispatch::IntegrationTest
  include RateLimits

  isolate_env "ASSISTANT_PROVIDER", "ASSISTANT_MODEL", "OLLAMA_BASE_URL", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"

  def with_empty_database
    Household.find_each { |household| Households::Destroy.call(household) }
    yield
  end

  def give_the_setup_code
    post setup_code_path, params: { setup_code: { code: SetupCodes::Renew.call.code } }
  end

  # The whole setup form is sent, as the press sends it; only the assistant's
  # step is read.
  def press_test(assistant)
    post setup_assistant_test_path, params: { setup: { account: { username: "ops", password: "a-long-password" }, assistant: assistant } },
                                    as: :turbo_stream
  end

  test "the typed key is tried and lists its models, and nothing is saved" do
    with_empty_database do
      give_the_setup_code
      tried = []
      listed = []
      check = ->(provider:, model:, api_key:, **) { tried << [ provider, model, api_key ] }
      models = lambda do |provider, api_key:, **|
        listed << [ provider, api_key ]
        %w[claude-haiku-4-5-20251001 claude-sonnet-4-5]
      end
      swapping(Assistant::Connection, :check!, check) do
        swapping(Assistant::Connection, :models, models) do
          press_test(provider: "anthropic", model: "claude-sonnet-4-5", anthropic_api_key: "sk-typed")
        end
      end

      assert_response :success
      assert_equal [ %w[anthropic claude-sonnet-4-5 sk-typed] ], tried
      assert_equal [ %w[anthropic sk-typed] ], listed
      assert_select "turbo-stream[action=replace][target=assistant-settings-connection] .status-badge--good", text: /Connected/
      assert_select "turbo-stream[action=replace][target=assistant-settings-models] datalist option[value='claude-sonnet-4-5']"
      assert_not Assistant::Setting.exists?
      assert_predicate Profile, :none?
    end
  end

  test "a server that doesn't answer says why, and leaves the name to be typed" do
    with_empty_database do
      give_the_setup_code
      offline = ->(**) { raise Assistant::Connection::Error, "the Ollama server at http://ollama.local:11434 isn't answering" }
      swapping(Assistant::Connection, :check!, offline) do
        swapping(Assistant::Connection, :models, ->(_provider, **) { [] }) do
          press_test(provider: "ollama", model: "qwen3:8b", ollama_url: "http://ollama.local:11434")
        end
      end

      assert_select "turbo-stream[target=assistant-settings-connection] .status-badge--critical", text: /Unreachable/
      assert_match "isn&#39;t answering", response.body
      assert_select "turbo-stream[target=assistant-settings-models] .help", text: /type the name/
    end
  end

  test "without the setup code nothing is asked of the provider" do
    with_empty_database do
      SetupCodes::Renew.call
      swapping(Assistant::Connection, :check!, ->(**) { flunk "the provider was asked" }) do
        press_test(provider: "ollama", model: "qwen3:8b")
      end

      assert_response :forbidden
    end
  end

  test "once anyone exists the press is gone" do
    press_test(provider: "ollama", model: "qwen3:8b")

    assert_redirected_to new_profile_session_path
  end

  test "every press asks the provider, so they are limited by address" do
    with_empty_database do
      give_the_setup_code
      counting_rate_limits do
        swapping(Assistant::Connection, :check!, ->(**) { true }) do
          swapping(Assistant::Connection, :models, ->(_provider, **) { [] }) do
            10.times { press_test(provider: "ollama", model: "qwen3:8b") }
            assert_response :success
            press_test(provider: "ollama", model: "qwen3:8b")
          end
        end
      end

      assert_response :too_many_requests
    end
  end
end
