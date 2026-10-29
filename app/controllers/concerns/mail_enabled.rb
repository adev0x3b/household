# frozen_string_literal: true

# Pages that exist only where the installation mails (Emails.enabled?):
# elsewhere they are a 404, like any page that isn't there, and nothing
# links to them.
module MailEnabled
  extend ActiveSupport::Concern

  private

  def mail_enabled!
    raise ActionController::RoutingError, "This installation sends no mail" unless Emails.enabled?
  end
end
