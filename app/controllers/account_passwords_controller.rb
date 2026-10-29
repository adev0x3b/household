# frozen_string_literal: true

# Changing one's password from the Account page (Accounts::PasswordChange).
# Every other browser is signed out by it, and what would outlast that
# stops (Profiles::AfterPasswordChange); this one stays signed in, and
# remembered if it was.
class AccountPasswordsController < ApplicationController
  include Devise::Controllers::Rememberable
  include AccountPage

  rate_limit_per_person(**AccountsController::PRESSES)

  def update
    authorize current_profile, :manage_account?
    change = Accounts::PasswordChange.new(current_profile, params.expect(password_change: %i[current_password password password_confirmation]))
    remembered = remember_me_is_active?(current_profile)
    unless change.save
      return render_page account_page(password_change: change), status: :unprocessable_content
    end

    Profiles::AfterPasswordChange.call(current_profile, device: cookies.signed[PushSubscriptionsController::DEVICE_COOKIE])
    bypass_sign_in(current_profile)
    remember_me(current_profile) if remembered
    toast_flash(:success, t("accounts.notices.password_changed"))
    redirect_to account_path, status: :see_other
  end
end
