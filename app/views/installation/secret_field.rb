# frozen_string_literal: true

# A secret of the installation's (Platform::KEYS): never filled back into
# the page, so a blank field keeps the saved value. Its placeholder says
# where the value in use comes from, and a saved one can be forgotten with
# the trash on its line.
class Views::Installation::SecretField < Views::Base
  # source: where the value in use comes from (:saved, :env or nil), when
  # it isn't Platform.source's, as for the relay's login.
  def initialize(form:, key:, label:, help: nil, source: ::Platform.source(key))
    @form = form
    @key = key
    @label = label
    @help = help
    @source = source
  end

  def view_template
    form_field(@form, @key, label: @label, help: @help, control: false) do |field|
      div(class: "control report-secret") do
        @form.password_field @key, value: "", class: "input", autocomplete: "new-password", spellcheck: "false", placeholder: placeholder,
                                   aria: field.aria
        forget if @source == :saved
      end
    end
  end

  private

  def placeholder
    case @source
    when :saved then saved
    when :env then t("installation.secret.from_env", variable: ::Platform::ENV_NAMES.fetch(@key))
    else t("installation.secret.none.#{@key}")
    end
  end

  def saved
    hint = ::Platform.saved.hint(@key)
    hint ? t("installation.secret.saved", last4: hint) : t("installation.secret.saved_password")
  end

  def forget
    name = t("installation.secret.names.#{@key}")
    render Components::ItemAction.new(href: value_admin_settings_path(@key), icon: "fa-trash", method: :delete, danger: true,
                                      label: t("installation.secret.clear", name: name), confirm: t("installation.secret.clear_confirm", name: name))
  end
end
