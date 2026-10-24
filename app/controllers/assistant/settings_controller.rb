# frozen_string_literal: true

# Which provider and model the assistant uses, and how it is tuned
# (Assistant::Setting), for every household at once: the admin's. A save
# needs no restart, because every chat reads the configuration again on its
# next reply. It waits for the admin's password (Admin::Sudo): a stolen
# session could otherwise send every household's chats to a server of its
# own. Testing the form and forgetting a key don't.
class Assistant::SettingsController < Admin::BaseController
  include Assistant::ConnectionAnswers

  FIELDS = %i[provider model ollama_url anthropic_api_key openai_api_key context_tokens temperature thinking_effort max_output_tokens].freeze

  def show
    render_page page(Assistant::Setting.for_form)
  end

  def update
    # A row of its own, because Assistant::Setting.saved is memoized and the
    # page still shows it as what is in use after a failed save.
    setting = (Assistant::Setting.first || Assistant::Setting.new).assign_settings(setting_params)
    setting.updated_by = current_profile
    if !sudo.passed?(params.dig(:assistant_setting, :password))
      render_page page(setting, wrong_password: true), status: :unprocessable_content
    elsif setting.save
      toast_flash(:success, t("assistant.settings.notices.saved"))
      redirect_to assistant_settings_path, status: :see_other
    else
      render_page page(setting), status: :unprocessable_content
    end
  end

  # The page loads this in a lazy frame, so it never waits on the provider.
  def check
    render connection_status(provider: Assistant.provider.to_s, model: Assistant.model), layout: false
  end

  # Checks the form's values without saving them.
  def test
    answer_connection_test((Assistant::Setting.first || Assistant::Setting.new).assign_settings(setting_params))
  end

  def models
    answer_model_list(params[:provider])
  end

  # Once the saved key is gone, the environment's key takes over, if any.
  def clear_key
    provider = params[:provider]
    setting = Assistant::Setting.first
    if setting.nil? || setting.api_key(provider).blank? ||
       setting.update(Assistant::Setting.key_column(provider) => nil, updated_by: current_profile)
      toast_flash(:success, t("assistant.settings.notices.key_cleared", provider: t("assistant.settings.providers.#{provider}.name")))
    else
      toast_flash(:alert, t("assistant.settings.notices.key_in_use", provider: t("assistant.settings.providers.#{provider}.name")))
    end
    redirect_to assistant_settings_path, status: :see_other
  end

  private

  def setting_params = params.fetch(:assistant_setting, {}).permit(*FIELDS)

  def page(setting, wrong_password: false)
    Views::Assistant::Settings::Show.new(setting: setting, saved: Assistant::Setting.saved, ask_password: sudo.required?, wrong_password: wrong_password)
  end
end
