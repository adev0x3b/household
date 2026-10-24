# frozen_string_literal: true

# The first setup's "You" step (Setup::Account): the person's name, how they
# sign in, and the language the app speaks to them.
class Views::Setup::Steps::Account < Views::Base
  def initialize(form:, section:)
    @form = form
    @section = section
  end

  def view_template
    render Components::Panel.new(title: t("setup.steps.account.title"), hint: t("setup.steps.account.hint")) do
      div(class: "report-fields") do
        text_field(:first_name, autocomplete: "given-name", required: true)
        text_field(:last_name, autocomplete: "family-name")
      end
      text_field(:username, autocomplete: "username", autocapitalize: "none", spellcheck: "false", required: true)
      text_field(:email, autocomplete: "email", type: "email", required: true)
      password_field(:password)
      password_field(:password_confirmation)
      locale_field
    end
  end

  private

  def text_field(attribute, type: "text", required: false, **options)
    form_field(@form, attribute, label: t("setup.steps.account.#{attribute}"), required:) do |field|
      @form.text_field attribute, type:, required:, class: "input", aria: field.aria, **options
    end
  end

  def password_field(attribute)
    render Components::PasswordField.new(form: @form, attribute:, label: t("setup.steps.account.#{attribute}"), new_password: true,
                                         errors: field_errors(@form, attribute))
  end

  def locale_field
    form_field(@form, :locale, label: t("setup.steps.account.locale"), help: t("setup.steps.account.locale_help"), select: true) do |field|
      @form.select :locale, I18n.available_locales.map { |locale| [ t("navbar.locale.names.#{locale}"), locale.to_s ] }, {}, aria: field.aria
    end
  end
end
