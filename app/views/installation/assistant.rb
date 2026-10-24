# frozen_string_literal: true

# Which model the assistant talks to (Installation::Assistant): the
# provider, how to reach it and the model. A card group of
# /assistant/settings and a step of the first setup. API keys are never
# shown back: a saved one is named by its last four characters, and the
# trash on its line forgets it.
class Views::Installation::Assistant < Views::Base
  PROVIDER_ICONS = { "ollama" => "fa-server", "anthropic" => "fa-asterisk", "openai" => "fa-circle-nodes" }.freeze

  # form: the builder the fields belong to; section: the Installation::Assistant.
  # saved: the Assistant::Setting in use, nil while the environment decides.
  # models_src: where the model field's suggestions load from, none without one.
  # test_url: where the model card's Test press tries the form's values; the
  # settings page has its own in its footer, with the answer in its status card.
  def initialize(form:, section:, saved: nil, models_src: nil, test_url: nil)
    @form = form
    @setting = section.setting
    @saved = saved
    @models_src = models_src
    @test_url = test_url
  end

  def view_template
    provider_card
    connection_card
    model_card
  end

  private

  def provider = @setting.provider.presence || ::Assistant.provider.to_s
  def provider_name(key) = t("assistant.settings.providers.#{key}.name")

  def provider_card
    render Components::Panel.new(title: t("assistant.settings.sections.provider"), hint: t("assistant.settings.sections.provider_hint")) do
      fieldset(class: "report-choices report-choices--row") do
        legend(class: "is-sr-only") { t("assistant.settings.sections.provider") }
        ::Assistant::Setting::PROVIDERS.each { |key| provider_choice(key) }
      end
    end
  end

  def provider_choice(key)
    label(class: "report-choice") do
      @form.radio_button :provider, key, checked: key == provider, data: { action: "change->assistant-settings#pick" }
      span(class: "report-choice__text") do
        strong do
          render Components::Icon.new(PROVIDER_ICONS.fetch(key))
          plain " #{provider_name(key)}"
        end
        span(class: "help") { t("assistant.settings.providers.#{key}.blurb") }
      end
    end
  end

  # Every provider's fields are on the page, so picking another shows its
  # group at once (assistant_settings_controller.js) without a request.
  def connection_card
    render Components::Panel.new(title: t("assistant.settings.sections.connection")) do
      ::Assistant::Setting::PROVIDERS.each do |key|
        div(class: "assistant-settings__connection-fields", hidden: key != provider,
            data: { assistant_settings_target: "connection", provider: key }) do
          key == "ollama" ? ollama_field : key_field(key)
        end
      end
    end
  end

  def ollama_field
    field(:ollama_url, t("assistant.settings.fields.ollama_url"), help: t("assistant.settings.fields.ollama_url_help")) do |field|
      @form.url_field :ollama_url, class: "input", placeholder: ::Assistant::DEFAULT_OLLAMA_URL, autocomplete: "off", aria: field.aria
    end
  end

  # The key is never filled back into the page, so a blank field keeps the
  # saved key; forgetting it is the trash button on its line.
  def key_field(key)
    column = ::Assistant::Setting.key_column(key)
    field(column, t("assistant.settings.fields.api_key", provider: provider_name(key)), help: t("assistant.settings.fields.api_key_help")) do |field|
      div(class: "report-secret") do
        @form.password_field column, value: "", class: "input", autocomplete: "new-password", spellcheck: "false",
                                     placeholder: key_placeholder(key), aria: field.aria
        if @saved&.api_key(key).present?
          render Components::ItemAction.new(href: key_assistant_settings_path(key), icon: "fa-trash", method: :delete, danger: true,
                                            label: t("assistant.settings.clear_key", provider: provider_name(key)),
                                            confirm: t("assistant.settings.clear_key_confirm", provider: provider_name(key)))
        end
      end
    end
  end

  def key_placeholder(key)
    case ::Assistant.key_source(key)
    when :saved then t("assistant.settings.fields.key_saved", last4: @saved.key_hint(key))
    when :env then t("assistant.settings.fields.key_env", variable: "#{key.upcase}_API_KEY")
    else t("assistant.settings.fields.key_none")
    end
  end

  def model_card
    render Components::Panel.new(title: t("assistant.settings.sections.model"), hint: t("assistant.settings.sections.model_hint")) do
      field(:model, t("assistant.settings.fields.model")) do |field|
        @form.text_field :model, required: true, class: "input", list: (Views::Assistant::Settings::ModelOptions::LIST_ID if @models_src),
                                 autocomplete: "off", spellcheck: "false", aria: field.aria
      end
      render Views::Assistant::Settings::ModelOptions.new(src: @models_src) if @models_src
      connection_test if @test_url
    end
  end

  # The press sends the whole form to its own route, which tries it without
  # saving; the fields of the other steps aren't checked for it.
  def connection_test
    div(class: "assistant-settings__test") do
      button(type: "submit", formaction: @test_url, formnovalidate: true, class: "modal__btn modal__btn--cancel") do
        render Components::Icon.new("fa-plug")
        whitespace
        plain t("assistant.settings.test")
      end
      render Views::Assistant::Settings::ConnectionStatus.new
    end
  end

  def field(name, text, help: nil, &)
    form_field(@form, name, label: text, help: help, record: @setting, &)
  end
end
