# frozen_string_literal: true

# A test mail to the admin themselves, pressed on /admin/emails: through
# the outbox and the relay like every mail, so how it went shows on that
# page. It ends a pause (Emails::RelayPause) too, since the admin has just
# fixed the settings or wants to know whether they are.
class Admin::TestMailsController < Admin::BaseController
  # Each test spends the installation's budget, which reminders need too.
  rate_limit_per_person to: 3, within: 15.minutes

  def create
    return refuse(t("admin.emails.test.unavailable")) unless Emails.enabled?

    Emails::RelayPause.clear
    Emails::Enqueue.call(current_profile, :test_mail)
    toast_flash(:notice, t("admin.emails.test.queued", address: current_profile.email))
    redirect_back_or_to admin_emails_path, status: :see_other
  end
end
