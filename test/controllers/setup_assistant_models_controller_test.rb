# frozen_string_literal: true

require "test_helper"

# The model list on the first setup's assistant step, for the provider
# picked, asked with what the environment gives. Only the browser that gave
# the setup code may ask.
class SetupAssistantModelsControllerTest < ActionDispatch::IntegrationTest
  isolate_env "ASSISTANT_PROVIDER", "ASSISTANT_MODEL", "OLLAMA_BASE_URL", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"

  def with_empty_database
    Household.find_each { |household| Households::Destroy.call(household) }
    yield
  end

  test "the list is the picked provider's" do
    with_empty_database do
      post setup_code_path, params: { setup_code: { code: SetupCodes::Renew.call.code } }
      models = ->(provider, **) { provider == "anthropic" ? %w[claude-haiku-4-5-20251001] : [] }
      swapping(Assistant::Connection, :models, models) do
        get setup_assistant_models_path(provider: "anthropic")
      end

      assert_response :success
      assert_select "turbo-frame#assistant-settings-models datalist option[value='claude-haiku-4-5-20251001']"
    end
  end

  test "without the setup code nothing is asked of the provider" do
    with_empty_database do
      SetupCodes::Renew.call
      swapping(Assistant::Connection, :models, ->(*, **) { flunk "the provider was asked" }) do
        get setup_assistant_models_path(provider: "anthropic")
      end

      assert_response :forbidden
    end
  end
end
