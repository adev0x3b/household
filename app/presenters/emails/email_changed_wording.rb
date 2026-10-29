# frozen_string_literal: true

module Emails
  # Another address took over (AccountMailer#email_changed).
  class EmailChangedWording < AccountNoticeWording
    private

    def key = "email_changed"
  end
end
