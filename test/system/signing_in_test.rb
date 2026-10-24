# frozen_string_literal: true

require "application_system_test_case"

class SigningInTest < ApplicationSystemTestCase
  test "signing in by username lands on home; signing out comes back to the sign-in page" do
    profiles(:alice).update!(password: "a-long-password")

    visit root_path
    assert_text I18n.t("sessions.new.title")
    fill_in I18n.t("sessions.new.login_placeholder"), with: "alice"
    fill_in I18n.t("sessions.new.password_placeholder"), with: "a-long-password"
    click_on I18n.t("sessions.new.submit")

    assert_current_path root_path
    assert_selector ".toast" # above the bottom bar on a phone: the top bar stays pressable meanwhile

    click_on I18n.t("navbar.account.label")
    assert_accessible "the account menu, open"
    click_on I18n.t("navbar.profile.logout")
    assert_text I18n.t("sessions.new.title")
  end
end
