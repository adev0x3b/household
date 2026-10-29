# frozen_string_literal: true

# The page a link to confirm an address opens, signed in as the person it
# was mailed to (Views::Accounts::EmailConfirmation), and its press, which
# confirms with the password in use (Accounts::EmailConfirmation). The token
# travels in the query and the form, never the path.
class AccountEmailConfirmationsController < ApplicationController
  include TokenInAddress

  rate_limit_per_person(**AccountsController::PRESSES, only: :create)

  def show
    authorize current_profile, :manage_account?
    render_page Views::Accounts::EmailConfirmation.new(confirmation: Accounts::EmailConfirmation.new(current_profile, token: params[:token].to_s))
  end

  def create
    authorize current_profile, :manage_account?
    confirmation = Accounts::EmailConfirmation.new(current_profile, params.expect(email_confirmation: %i[token current_password]))
    unless confirmation.save
      return refuse(t("accounts.email_confirmation.problems.#{confirmation.problem}")) if confirmation.problem

      return render_page Views::Accounts::EmailConfirmation.new(confirmation:), status: :unprocessable_content
    end

    toast_flash(:success, t("accounts.notices.email_confirmed", address: current_profile.email))
    redirect_to account_path, status: :see_other
  end
end
