# frozen_string_literal: true

# Mail to the admin about the installation itself.
class AdminMailer < ApplicationMailer
  # The test sent from /admin/emails: if it arrives, mail goes out.
  def test_mail
    profile = params.fetch(:profile)
    compose(to: profile.email, wording: Emails::TestMailWording.new(profile, page_url: admin_emails_url))
  end
end
