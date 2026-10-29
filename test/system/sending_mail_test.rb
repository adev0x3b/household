# frozen_string_literal: true

require "application_system_test_case"

# The admin's page of mail as the admin reads it: what waits and what
# couldn't go out, each with why, and a test mail sent from the page.
class SendingMailTest < ApplicationSystemTestCase
  setup do
    @admin = profiles(:alice).tap { _1.update!(role: :admin, email_confirmed_at: 1.day.ago) }
    sign_in @admin
  end

  test "what waits and what failed, each with why, and a test mail sent from the page" do
    now = Time.current
    OutgoingEmail.create!(profile: profiles(:bob), kind: :reminder, not_before: now + 12.minutes, expires_at: now + 1.hour, reason: :over_budget)
    OutgoingEmail.create!(profile: profiles(:carol), kind: :email_confirmation, status: :failed, attempts: 1, not_before: now - 1.hour,
                          expires_at: now, claimed_at: now - 1.hour, reason: :refused, detail: "550 5.1.1 [address]: Recipient address rejected")

    with_relay do
      visit admin_emails_path
      assert_selector ".emails__reason", text: I18n.t("admin.emails.reasons.over_budget")
      assert_selector ".emails__reason", text: I18n.t("admin.emails.reasons.refused")
      assert_selector ".emails__detail", text: "550 5.1.1 [address]: Recipient address rejected"

      click_on I18n.t("admin.emails.test.label")
      assert_text I18n.t("admin.emails.test.queued", address: @admin.email)
    end
    assert_predicate OutgoingEmail.test_mail.where(profile: @admin), :exists?
  end
end
