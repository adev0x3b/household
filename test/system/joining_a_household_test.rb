# frozen_string_literal: true

require "application_system_test_case"

# A household grows by invitation: a member invites someone, hands over
# the link shown once, and the invitee picks a username and a password.
class JoiningAHouseholdTest < ApplicationSystemTestCase
  test "a member invites someone, who follows the link, chooses how to sign in and is in" do
    sign_in profiles(:alice)
    visit household_path

    click_on I18n.t("households.invite.title")
    within(".modal") do
      fill_in I18n.t("households.invite.email_label"), with: "erin@example.com"
      fill_in I18n.t("households.invite.first_name_label"), with: "Erin"
      click_on I18n.t("households.invite.submit")
    end
    assert_text I18n.t("households.notices.invited", email: "erin@example.com")
    link = find(".household__link-url").value

    using_session(:erin) do
      visit link
      assert_text I18n.t("invitations.edit.title", household: households(:example).name)
      fill_in I18n.t("invitations.edit.username_label"), with: "erin"
      fill_in I18n.t("invitations.edit.password_label"), with: "a long enough password"
      fill_in I18n.t("invitations.edit.password_confirmation_label"), with: "a long enough password"
      assert_accessible "accepting an invitation"
      click_on I18n.t("invitations.edit.submit")

      assert_current_path root_path
    end
    erin = Profile.find_by!(username: "erin")
    assert_equal [ households(:example), "Erin" ], [ erin.household, erin.first_name ]
    assert erin.invitation_accepted_at
  end
end
