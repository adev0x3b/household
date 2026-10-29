# frozen_string_literal: true

# /account: the signed-in person's own account (Views::Accounts::Show): the
# address the app mails and the password. Its presses are controllers of
# their own (AccountEmailChangesController, AccountPasswordsController, …),
# which draw this page again with their form's errors.
class AccountsController < ApplicationController
  include AccountPage

  # One limit for every press of the page together, per person: what they
  # ask for is checked against the password, which mustn't be guessed at
  # from one press while another waits, and some of them mail.
  PRESSES = { to: 10, within: 15.minutes, scope: "account" }.freeze

  def show
    authorize current_profile, :manage_account?
    render_page account_page
  end
end
