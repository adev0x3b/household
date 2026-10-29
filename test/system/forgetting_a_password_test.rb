# frozen_string_literal: true

require "application_system_test_case"

# A forgotten password, from the sign-in page where the installation mails:
# the page that asks for a link, and its answer, the same whoever was asked for.
class ForgettingAPasswordTest < ApplicationSystemTestCase
  test "the sign-in page leads to asking for a link, whose answer comes back on the sign-in page" do
    with_relay do
      visit new_profile_session_path
      click_on I18n.t("sessions.new.forgot_link")
      assert_selector "h1", text: I18n.t("passwords.new.title")

      fill_in I18n.t("passwords.new.login_label"), with: "nobody"
      click_on I18n.t("passwords.new.submit")

      assert_text I18n.t("passwords.notices.asked", minutes: 30)
      assert_selector "h1", text: I18n.t("sessions.new.title")
    end
  end
end
