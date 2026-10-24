# frozen_string_literal: true

require "test_helper"

# /assistant/settings: admins choose the provider, its key or server, the
# model and its tuning; keys never come back to the page; nobody else gets in.
class Assistant::SettingsControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-enough-password"

  isolate_env "ASSISTANT_PROVIDER", "ASSISTANT_MODEL", "OLLAMA_MODEL", "OLLAMA_BASE_URL", "ANTHROPIC_API_KEY",
              "OPENAI_API_KEY"

  setup do
    @admin = profiles(:alice).tap { _1.update!(role: :admin, password: PASSWORD, password_confirmation: PASSWORD) }
    sign_in @admin
  end

  def reachable(&) = swapping(Assistant::Connection, :check!, ->(**) { true }, &)
  def listing(*models, &) = swapping(Assistant::Connection, :models, ->(_provider, **) { models }, &)

  test "a member who isn't an admin is turned away" do
    sign_in profiles(:bob)

    get assistant_settings_path
    assert_redirected_to root_path
    patch assistant_settings_path, params: { assistant_setting: { password: PASSWORD, provider: "openai", model: "x", openai_api_key: "sk" } }
    assert_redirected_to root_path
    assert_not Assistant::Setting.exists?
  end

  test "the page says where conversations go, and what each household used this month" do
    chat = assistant_chat(profiles(:alice))
    chat.assistant_messages.create!(role: "user", content: "hi")
    RubyLLM::ActiveRecord::Usage.create!(chat: chat, model: "m", provider: "ollama", operation: "chat", status: "succeeded", input_tokens: 1234, output_tokens: 56)

    reachable { get assistant_settings_path }
    assert_response :success
    assert_select ".report-status", text: /stay on the household's own server/
    assert_select ".assistant-settings__usage", text: /#{profiles(:alice).household.name}.*1[,.]234/m

    ENV["ASSISTANT_PROVIDER"] = "anthropic"
    ENV["ANTHROPIC_API_KEY"] = "sk-test"
    reachable { get assistant_settings_path }
    assert_select ".report-status", text: /leave the server: Anthropic/
  end

  test "until saved, the page shows the environment's configuration" do
    ENV["OLLAMA_BASE_URL"] = "http://ollama.local:11434"
    ENV["OLLAMA_MODEL"] = "qwen3-8b-household"

    get assistant_settings_path
    assert_response :success
    assert_select ".report-status", text: /Ollama.*qwen3-8b-household.*environment/m
    assert_select "input[type=radio][name='assistant_setting[provider]'][value=ollama][checked]"
    assert_select "input[name='assistant_setting[ollama_url]'][value='http://ollama.local:11434']"
    assert_select "turbo-frame#assistant-settings-connection[src='#{check_assistant_settings_path}'][loading=lazy]"
    assert_select "turbo-frame#assistant-settings-models[src*='provider=ollama']"
    assert_select "div[data-assistant-settings-target=connection][data-provider=anthropic][hidden]"
  end

  test "saving applies at once, records who did it, and never shows a key back" do
    patch assistant_settings_path, params: { assistant_setting: {
      provider: "anthropic", model: "claude-haiku-4-5-20251001", anthropic_api_key: "sk-ant-secret-WXYZ", temperature: "", context_tokens: "200000",
      password: PASSWORD
    } }
    assert_redirected_to assistant_settings_path

    setting = Assistant::Setting.sole
    assert_equal @admin, setting.updated_by
    assert_equal :anthropic, Assistant.provider
    assert_nil Assistant.temperature

    follow_redirect!
    assert_no_match "sk-ant-secret", response.body
    assert_select "input[name='assistant_setting[anthropic_api_key]'][value=''][placeholder*=WXYZ]"
    assert_select ".report-status", text: /claude-haiku-4-5-20251001.*by alice/m
    assert_select "a.item-action--danger[href='#{key_assistant_settings_path("anthropic")}'][data-turbo-method=delete]"
  end

  test "a blank key keeps the saved one; an invalid save shows what's wrong and changes nothing" do
    Assistant::Setting.create!(provider: "openai", model: "gpt-5.6-luna", openai_api_key: "sk-keep")

    patch assistant_settings_path, params: { assistant_setting: { password: PASSWORD, provider: "openai", model: "gpt-5.6", openai_api_key: "" } }
    assert_equal "sk-keep", Assistant::Setting.sole.openai_api_key

    patch assistant_settings_path, params: { assistant_setting: { password: PASSWORD, provider: "ollama", model: "qwen3; rm", ollama_url: "ollama.local" } }
    assert_response :unprocessable_content
    assert_select ".notice--critical li", text: /Model can only have/
    assert_select ".field.is-invalid input[name='assistant_setting[ollama_url]'][aria-invalid=true]"
    assert_equal "openai", Assistant::Setting.sole.provider
  end

  test "the connection line: the configuration in use, or the form's values when tested" do
    reachable do
      get check_assistant_settings_path
      assert_select "turbo-frame#assistant-settings-connection .status-badge--good", text: /Connected/
    end

    offline = ->(**) { raise Assistant::Connection::Error, "the Ollama server at http://ollama.local:11434 isn't answering" }
    swapping(Assistant::Connection, :check!, offline) do
      listing do
        post test_assistant_settings_path, params: { assistant_setting: { provider: "ollama", model: "qwen3:8b", ollama_url: "http://ollama.local:11434" } },
                                           as: :turbo_stream
      end
    end
    assert_select "turbo-stream[action=replace][target=assistant-settings-connection]"
    assert_match "isn&#39;t answering", response.body
    assert_match "not saved", response.body
    assert_not Assistant::Setting.exists?, "testing never saves"
  end

  test "the model list is the chosen provider's" do
    swapping(Assistant::Connection, :models, ->(provider, **) { provider == "anthropic" ? %w[claude-haiku-4-5-20251001] : [] }) do
      get models_assistant_settings_path(provider: "anthropic")
    end
    assert_select "turbo-frame#assistant-settings-models datalist option[value='claude-haiku-4-5-20251001']"
  end

  test "testing lists the models a key just typed reaches, before it is saved" do
    Assistant::Setting.create!(provider: "anthropic", model: "claude-haiku-4-5-20251001", ollama_url: "http://ollama.local:11434", anthropic_api_key: "sk-saved")
    asked = []
    models = lambda do |provider, api_key:, **|
      asked << [ provider, api_key ]
      %w[claude-haiku-4-5-20251001 claude-sonnet-4-5]
    end
    swapping(Assistant::Connection, :models, models) do
      reachable do
        post test_assistant_settings_path, params: { assistant_setting: { provider: "anthropic", model: "claude-sonnet-4-5", anthropic_api_key: "sk-typed" } },
                                           as: :turbo_stream
        post test_assistant_settings_path, params: { assistant_setting: { provider: "anthropic", model: "claude-sonnet-4-5", anthropic_api_key: "" } },
                                           as: :turbo_stream
      end
    end

    assert_equal [ %w[anthropic sk-typed], %w[anthropic sk-saved] ], asked, "a blank key lists with the saved one"
    assert_select "turbo-stream[action=replace][target=assistant-settings-models] datalist option[value='claude-sonnet-4-5']"
    assert_equal "sk-saved", Assistant::Setting.sole.anthropic_api_key
  end

  test "a saved key can be forgotten, unless the provider in use has no other" do
    Assistant::Setting.create!(provider: "ollama", model: "qwen3:8b", ollama_url: "http://ollama.local:11434", openai_api_key: "sk-old")
    delete key_assistant_settings_path("openai")
    assert_nil Assistant::Setting.sole.openai_api_key

    Assistant::Setting.sole.update!(provider: "openai", openai_api_key: "sk-only")
    delete key_assistant_settings_path("openai")
    assert_equal "sk-only", Assistant::Setting.sole.reload.openai_api_key
    assert_match "provider in use", flash[:alert]
  end

  test "a save waits for the admin's password; trying the form doesn't" do
    get assistant_settings_path
    assert_select "input[type=password][name='assistant_setting[password]']:not([required])"

    patch assistant_settings_path, params: { assistant_setting: { provider: "ollama", model: "qwen3:8b", ollama_url: "http://elsewhere.example:11434", password: "a guess" } }
    assert_response :unprocessable_content
    assert_select ".notice--critical", text: /isn't your password/
    assert_not Assistant::Setting.exists?

    reachable do
      listing { post test_assistant_settings_path, params: { assistant_setting: { provider: "ollama", model: "qwen3:8b" } }, as: :turbo_stream }
    end
    assert_response :success
  end
end
