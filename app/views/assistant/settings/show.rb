# frozen_string_literal: true

# The assistant's settings: what is in use, then one form for the provider,
# how to reach it and the model (Views::Installation::Assistant, as the first
# setup asks them), and its tuning.
class Views::Assistant::Settings::Show < Views::Base
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::NumberWithDelimiter

  # setting is what the form shows: the saved row, the environment's values,
  # or a rejected save. saved is the row in use, nil while .env decides.
  # ask_password: the save waits for the admin's password (Admin::Sudo);
  # wrong_password: the last one typed wasn't theirs.
  def initialize(setting:, saved:, ask_password: false, wrong_password: false)
    @setting = setting
    @saved = saved
    @ask_password = ask_password
    @wrong_password = wrong_password
  end

  def page_title = t("assistant.settings.title")

  def view_template
    div(class: "report-page assistant-settings") do
      render Components::PageHeader.new(title: t("assistant.settings.title"))
      p(class: "report-hint") { t("assistant.settings.hint") }
      status_card
      usage_card
      render Components::ErrorSummary.new(record: @setting)
      form_with(model: @setting, url: assistant_settings_path, method: :post, scope: :assistant_setting, class: "report-form",
                data: { controller: "assistant-settings", assistant_settings_models_url_value: models_assistant_settings_path }) do |f|
        render Views::Installation::Assistant.new(form: f, section: ::Installation::Assistant.new(@setting), saved: @saved,
                                                  models_src: models_assistant_settings_path(provider: provider))
        advanced_section(f)
        render Views::Admin::SettingsPassword.new(form: f, wrong: @wrong_password) if @ask_password
        footer
      end
    end
  end

  private

  def provider = @setting.provider.presence || ::Assistant.provider.to_s
  def provider_name(key) = t("assistant.settings.providers.#{key}.name")

  def status_card
    render Components::Report::StatusCard.new(tone: :neutral) do |card|
      card.head do
        render Components::StatusBadge.new(tone: :neutral, icon: Views::Installation::Assistant::PROVIDER_ICONS.fetch(::Assistant.provider.to_s, "fa-robot"),
                                           label: provider_name(::Assistant.provider))
        strong(class: "report-mono") { ::Assistant.model }
        card.time { changed_line }
      end
      render Views::Assistant::Settings::ConnectionStatus.new(src: check_assistant_settings_path)
      card.times([ context_line, data_line ])
    end
  end

  def changed_line
    return t("assistant.settings.status.from_environment") unless @saved

    if @saved.updated_by
      t("assistant.settings.status.changed_by", time: time_ago_in_words(@saved.updated_at), name: @saved.updated_by.username)
    else
      t("assistant.settings.status.changed", time: time_ago_in_words(@saved.updated_at))
    end
  end

  def context_line
    tokens = ::Assistant.context_tokens
    tokens ? t("assistant.settings.status.context", tokens: number_with_delimiter(tokens)) : t("assistant.settings.status.no_context")
  end

  # Where chats go: the household's own server, or a cloud provider.
  def data_line
    ::Assistant.cloud? ? t("assistant.settings.status.cloud", provider: provider_name(::Assistant.provider)) : t("assistant.settings.status.local")
  end

  def usage_card
    render Views::Assistant::Settings::UsageCard.new(rows: ::Assistant::Usage.by_household)
  end

  # Folded away because the defaults suit most models; it opens when one of
  # its values was refused.
  def advanced_section(f)
    open = (@setting.errors.attribute_names & %i[context_tokens temperature thinking_effort max_output_tokens]).any?
    render Components::Disclosure.new(key: "assistant-settings-advanced", title: t("assistant.settings.sections.advanced"), open: open,
                                      result: -> { plain advanced_summary }) do
      div(class: "report-fields") do
        number_field(f, :context_tokens, step: 1, min: 1024, help: t("assistant.settings.fields.context_tokens_help"))
        number_field(f, :temperature, step: 0.05, min: 0, max: 2, help: t("assistant.settings.fields.temperature_help"))
        thinking_field(f)
        number_field(f, :max_output_tokens, step: 1, min: 256, help: max_output_tokens_help)
      end
    end
  end

  def advanced_summary
    t("assistant.settings.advanced_summary",
      context: @setting.context_tokens ? number_with_delimiter(@setting.context_tokens) : t("assistant.settings.unset"),
      temperature: @setting.temperature ? number_with_delimiter(@setting.temperature) : t("assistant.settings.not_sent"),
      thinking: t("assistant.settings.thinking.#{@setting.thinking_effort.presence || "default"}"))
  end

  def number_field(f, name, help:, **range)
    field(f, name, t("assistant.settings.fields.#{name}"), help: help) do |field|
      f.number_field name, value: number_value(@setting.public_send(name)), class: "input", inputmode: "decimal", aria: field.aria, **range
    end
  end

  def thinking_field(f)
    field(f, :thinking_effort, t("assistant.settings.fields.thinking_effort"), help: t("assistant.settings.fields.thinking_effort_help")) do |field|
      div(class: "select is-fullwidth") do
        efforts = select_options(::Assistant::Setting::THINKING) { |effort| t("assistant.settings.thinking.#{effort}") }
        f.select :thinking_effort, efforts, { include_blank: t("assistant.settings.thinking.default") }, aria: field.aria
      end
    end
  end

  # Both buttons submit the same form: Test posts it to its own route,
  # which tries it without saving, and Save sends it as the update.
  def footer
    div(class: "report-footer") do
      button(type: "submit", formaction: test_assistant_settings_path, class: "modal__btn modal__btn--cancel") do
        render Components::Icon.new("fa-plug")
        whitespace
        plain t("assistant.settings.test")
      end
      button(type: "submit", name: "_method", value: "patch", class: "modal__btn modal__btn--primary") do
        render Components::Icon.new("fa-floppy-disk")
        whitespace
        plain t("assistant.settings.save")
      end
    end
  end

  def field(f, name, text, help: nil, &)
    form_field(f, name, label: text, help: help, &)
  end

  def max_output_tokens_help
    t("assistant.settings.fields.max_output_tokens_help", tokens: number_with_delimiter(::Assistant::DEFAULT_MAX_OUTPUT_TOKENS))
  end
end
