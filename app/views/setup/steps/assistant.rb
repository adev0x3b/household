# frozen_string_literal: true

# The first setup's assistant step: the same provider and model cards as
# /assistant/settings (Views::Installation::Assistant), with the provider's
# models to pick from and a Test press, asked only while the installation
# allows the assistant (the previous step's switch). Its tuning keeps the
# defaults until the admin changes it there. The switch is named as the
# setup's form names it (Views::Setup::Show).
class Views::Setup::Steps::Assistant < Views::Base
  def initialize(form:, section:)
    @form = form
    @section = section
  end

  def view_template
    div(class: "setup__group", data: { controller: "assistant-settings", assistant_settings_models_url_value: setup_assistant_models_path,
                                       setup_wizard_title: t("setup.steps.assistant.title"),
                                       setup_wizard_when: "setup[#{::Installation::Allowances.param_key}][assistant]" }) do
      render Views::Installation::Assistant.new(form: @form, section: @section, models_src: setup_assistant_models_path(provider: provider),
                                                test_url: setup_assistant_test_path)
    end
  end

  private

  def provider = @section.provider.presence || ::Assistant.provider.to_s
end
