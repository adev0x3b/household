# frozen_string_literal: true

# The account page (Views::Accounts::Show) as each of its controllers draws
# it: the signed-in person, whether the app mails, what it may mail them,
# whether their link to confirm an address is still to go out, and how many
# of their reminders couldn't be mailed lately; a press whose form was
# refused hands it that form, to draw with its errors.
module AccountPage
  extend ActiveSupport::Concern

  private

  def account_page(**forms)
    Views::Accounts::Show.new(profile: current_profile, mail: Emails.enabled?,
                              reminders_by_mail: Emails.for_reminders(current_profile) != :off,
                              password_link_by_mail: Profiles::RequestPasswordLink.mailable?(current_profile),
                              confirmation_on_its_way: OutgoingEmail.confirmation_on_its_way?(current_profile),
                              reminders_not_mailed: OutgoingEmail.reminders_not_mailed(current_profile), **forms)
  end
end
