# frozen_string_literal: true

module Emails
  # The password changed (AccountMailer#password_changed).
  class PasswordChangedWording < AccountNoticeWording
    private

    def key = "password_changed"
  end
end
