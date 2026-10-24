# frozen_string_literal: true

# The password of the demo household's accounts (Installation::DemoPassword).
class Views::Installation::DemoPassword < Views::Base
  def initialize(form:, section:)
    @form = form
    @section = section
  end

  def view_template
    render Components::Panel.new(title: t("installation.demo_password.title"), hint: t("installation.demo_password.hint")) do
      render Views::Installation::SecretField.new(form: @form, key: :demo_password, label: t("installation.secret.names.demo_password"))
    end
  end
end
