# frozen_string_literal: true

module Emails
  module Kinds
    # A test the admin sends themselves from /admin/emails, to see mail go
    # out: to their own address, confirmed or not, since it carries
    # nothing but the test.
    class TestMail < Kind
      def self.key = :test_mail

      def self.waits_at_most = 15.minutes

      # Not account mail: a test pressed again and again never takes what
      # is kept for someone's link to set a password.
      def self.account? = false

      # The admin's own, not their household's: the press is limited
      # (Admin::TestMailsController), and the installation's budget counts it.
      def self.room_in?(_household, _now) = true

      def message
        return unless profile.admin?

        Outgoing.new(mail: AdminMailer.with(profile: profile).test_mail.message, rows: rows)
      end
    end
  end
end
