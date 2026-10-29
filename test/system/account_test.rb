# frozen_string_literal: true

require "application_system_test_case"

# The Account page as its person uses it: reached from the account menu,
# a new password set with the one in use, and a new address that waits for
# the link mailed to it, which opens a page of its own.
class AccountTest < ApplicationSystemTestCase
  PASSWORD = "alice's long password"

  setup do
    @alice = profiles(:alice)
    @alice.update!(password: PASSWORD, password_confirmation: PASSWORD)
    sign_in @alice
  end

  test "a new password, set from the account menu with the one in use" do
    visit root_path
    click_on I18n.t("navbar.account.label")
    within("#account-menu-panel") { click_on I18n.t("navbar.links.account") }
    assert_selector "h1", text: I18n.t("accounts.show.title")

    change_password(current: "not the password")
    assert_text I18n.t("activemodel.errors.models.accounts/password_change.attributes.current_password.invalid")
    assert_accessible "the password form, refused"

    change_password(current: PASSWORD)
    assert_text I18n.t("accounts.notices.password_changed")
    assert @alice.reload.valid_password?("a new long password")
  end

  test "a new address waits for its link, and the link opens a page that confirms it" do
    with_relay do
      visit account_path
      within("form[action='#{account_email_change_path}']") do
        fill_in I18n.t("accounts.show.change_address.email"), with: "alice@new.example"
        fill_in I18n.t("accounts.show.current_password"), with: PASSWORD
        click_on I18n.t("accounts.show.change_address.submit")
      end
      assert_text I18n.t("accounts.show.waiting.body", address: "alice@new.example")
      assert_accessible "a new address waiting for its link"

      visit account_email_confirmation_path(token: @alice.reload.email_confirmation_token!)
      assert_accessible "the page a link to confirm an address opens"
      fill_in I18n.t("accounts.show.current_password"), with: PASSWORD
      click_on I18n.t("accounts.email_confirmation.submit")

      assert_text I18n.t("accounts.notices.email_confirmed", address: "alice@new.example")
      assert_selector ".account__value", text: "alice@new.example"
    end
  end

  private

  def change_password(current:)
    within("form[action='#{account_password_path}']") do
      fill_in I18n.t("accounts.show.current_password"), with: current
      fill_in I18n.t("accounts.show.change_password.password"), with: "a new long password"
      fill_in I18n.t("accounts.show.change_password.password_confirmation"), with: "a new long password"
      click_on I18n.t("accounts.show.change_password.submit")
    end
  end
end
