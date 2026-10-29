# frozen_string_literal: true

# The link that confirms an address, mailed again from the Account page
# (Profiles::SendEmailConfirmation).
class AccountEmailConfirmationLinksController < ApplicationController
  rate_limit_per_person(**AccountsController::PRESSES)

  def create
    authorize current_profile, :manage_account?
    result = Profiles::SendEmailConfirmation.call(current_profile)
    return refuse(t("accounts.errors.#{result.error}", count: Emails::ConfirmationAllowance::PER_DAY)) if result.failure?

    toast_flash(:notice, t("accounts.notices.link_sent", address: current_profile.address_to_confirm))
    redirect_to account_path, status: :see_other
  end
end
