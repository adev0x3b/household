# frozen_string_literal: true

# What the installation mails and through which relay (Installation::Mail):
# the switch, the relay's fields, its password as a secret, and the
# budgets. A relay field left empty follows the environment, whose value
# is its placeholder.
class Views::Installation::Mail < Views::Base
  # form: the builder for this section's fields (fields_for), section: the Installation::Mail.
  def initialize(form:, section:)
    @form = form
    @section = section
  end

  def view_template
    render Components::Panel.new(title: t("installation.mail.title"), hint: t("installation.mail.hint")) do
      fieldset(class: "report-choices") do
        legend(class: "is-sr-only") { t("installation.mail.title") }
        switch
      end
      div(class: "report-fields") do
        relay_field(:smtp_host, help: t("installation.mail.smtp_host_help"))
        relay_field(:smtp_port, inputmode: "numeric")
        tls_field
      end
      div(class: "report-fields") do
        relay_field(:smtp_username)
        render Views::Installation::SecretField.new(form: @form, key: :smtp_password, label: t("installation.mail.smtp_password"),
                                                    source: ::Emails::RelaySettings.source(:smtp_password))
        relay_field(:mail_from, help: t("installation.mail.mail_from_help"))
      end
      div(class: "report-fields") do
        count_field(:mails_per_hour)
        count_field(:mails_per_day)
        count_field(:reminder_mails_per_day)
      end
    end
  end

  private

  def switch
    label(class: "report-choice") do
      @form.check_box :outgoing_mail, aria: { describedby: @form.field_id(:outgoing_mail, :help) }
      span(class: "report-choice__text") do
        strong { t("installation.mail.outgoing_mail.name") }
        span(class: "help", id: @form.field_id(:outgoing_mail, :help)) { t("installation.mail.outgoing_mail.help") }
      end
    end
  end

  def relay_field(name, help: nil, inputmode: nil)
    form_field(@form, name, label: t("installation.mail.#{name}"), help: help) do |field|
      @form.text_field name, class: "input", autocomplete: "off", spellcheck: "false", autocapitalize: "none", inputmode: inputmode,
                             placeholder: placeholder(name), aria: field.aria
    end
  end

  # Where an empty field's value comes from: the environment's, when the
  # relay in use takes it (Emails::RelaySettings.source), else what an
  # empty one means.
  def placeholder(name)
    if ::Emails::RelaySettings.source(name) == :env
      t("installation.mail.from_env", value: ::Platform.env_value(name), variable: ::Platform::ENV_NAMES.fetch(name))
    else
      t("installation.mail.placeholders.#{name}")
    end
  end

  def tls_field
    form_field(@form, :smtp_tls, label: t("installation.mail.smtp_tls"), control: false) do |field|
      div(class: "control") do
        div(class: "select is-fullwidth") do
          @form.select :smtp_tls, ::Emails::RelaySettings::TLS_MODES.map { [ t("installation.mail.tls_modes.#{_1}"), _1 ] },
                       { include_blank: placeholder(:smtp_tls) }, aria: field.aria
        end
      end
    end
  end

  # A whole number, empty for the default.
  def count_field(name)
    limit = ::Platform.limit(name)
    form_field(@form, name, label: t("installation.mail.#{name}"), help: t("installation.mail.#{name}_help")) do |field|
      @form.number_field name, min: limit.minimum, step: 1, inputmode: "numeric", placeholder: t("installation.mail.default", count: limit.default),
                               class: "input", aria: field.aria
    end
  end
end
