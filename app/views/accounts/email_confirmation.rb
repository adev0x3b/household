# frozen_string_literal: true

# The page a link to confirm an address opens (AccountEmailConfirmationsController):
# the address, and a form that confirms it with the password in use; or why
# the link can't (Accounts::EmailConfirmation#problem). Opening it changes
# nothing, so a mail scanner that follows the link confirms nothing.
class Views::Accounts::EmailConfirmation < Views::Base
  include Phlex::Rails::Helpers::FormWith

  # confirmation: the form, as a refused press left it or fresh, holding
  # the link's token.
  def initialize(confirmation:)
    @confirmation = confirmation
  end

  def page_title = t("accounts.email_confirmation.title")

  def view_template
    div(class: "report-page account") do
      render Components::PageHeader.new(title: t("accounts.email_confirmation.title"), back_href: account_path, back_label: t("accounts.show.title"))
      @confirmation.problem ? problem : form
    end
  end

  private

  def problem
    render Components::Panel.new(title: t("accounts.email_confirmation.problem_title")) do
      p { t("accounts.email_confirmation.problems.#{@confirmation.problem}") }
      div(class: "account__actions") { a(href: account_path, class: "modal__btn modal__btn--cancel") { t("accounts.email_confirmation.to_account") } }
    end
  end

  def form
    render Components::Panel.new(title: @confirmation.address) do
      form_with(model: @confirmation, scope: :email_confirmation, url: account_email_confirmation_path, method: :post, class: "report-form") do |f|
        render Components::ErrorSummary.new(record: @confirmation)
        p { t("accounts.email_confirmation.body") }
        f.hidden_field :token
        render Components::PasswordField.new(form: f, attribute: :current_password, label: t("accounts.show.current_password"),
                                             errors: Forms::Errors.new(f.object).for(:current_password))
        div(class: "account__actions") { button(type: "submit", class: "modal__btn modal__btn--primary") { t("accounts.email_confirmation.submit") } }
      end
    end
  end
end
