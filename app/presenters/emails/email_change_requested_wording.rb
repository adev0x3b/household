# frozen_string_literal: true

module Emails
  # Another address was asked for (AccountMailer#email_change_requested).
  class EmailChangeRequestedWording < AccountNoticeWording
    private

    def key = "email_change_requested"
  end
end
