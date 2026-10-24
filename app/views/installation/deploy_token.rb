# frozen_string_literal: true

# The GitHub token behind /admin/deployment's buttons (Installation::DeployToken),
# and when it expires, as GitHub last said.
class Views::Installation::DeployToken < Views::Base
  # token_expiry: the saved token's (Delivery::TokenExpiry).
  def initialize(form:, section:, token_expiry:)
    @form = form
    @section = section
    @token_expiry = token_expiry
  end

  def view_template
    render Components::Panel.new(title: t("installation.deploy_token.title"),
                                 hint: t("installation.deploy_token.hint", repository: ::Deployment.repositories.to_sentence)) do
      render Views::Installation::SecretField.new(form: @form, key: :deploy_dispatch_token, label: t("installation.secret.names.deploy_dispatch_token"))
      expiry if @token_expiry.known?
    end
  end

  private

  def expiry
    date = l(@token_expiry.expires_at.in_time_zone.to_date, format: :long)
    if @token_expiry.expired?
      p(class: "help is-danger admin-settings__expiry") { t("installation.deploy_token.expired", date: date) }
    elsif @token_expiry.soon?
      p(class: "help is-warning admin-settings__expiry") { t("installation.deploy_token.expires_soon", days: @token_expiry.days_left) }
    else
      p(class: "help admin-settings__expiry") { t("installation.deploy_token.expires", date: date) }
    end
  end
end
