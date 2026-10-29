# frozen_string_literal: true

# Asking for another address (Accounts::EmailChange), and taking back one
# still waiting for its link, which then stops working.
class AccountEmailChangesController < ApplicationController
  include AccountPage

  rate_limit_per_person(**AccountsController::PRESSES, only: :create)

  def create
    authorize current_profile, :manage_account?
    change = Accounts::EmailChange.new(current_profile, params.expect(email_change: %i[email current_password]))
    unless change.save
      return render_page account_page(email_change: change), status: :unprocessable_content
    end

    if current_profile.unconfirmed_email
      toast_flash(:notice, t("accounts.notices.link_sent", address: current_profile.unconfirmed_email))
    else
      toast_flash(:success, t("accounts.notices.email_changed", address: current_profile.email))
    end
    redirect_to account_path, status: :see_other
  end

  def destroy
    authorize current_profile, :manage_account?
    current_profile.update!(unconfirmed_email: nil)
    redirect_back_after_save account_path, notice: t("accounts.notices.email_kept", address: current_profile.email)
  end
end
