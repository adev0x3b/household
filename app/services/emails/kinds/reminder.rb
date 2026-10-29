# frozen_string_literal: true

module Emails
  module Kinds
    # The reminders a person asked for by email too (Reminders::DispatchJob),
    # in one mail for those that fell due together. Not account mail, and
    # counted against the household's own budget (Emails::ReminderAllowance).
    # At its turn a reminder goes only while it still asks for email, its
    # person may read the series and the day is still to do and not yet due
    # (Reminders::StillDue); the rest are dropped.
    class Reminder < Kind
      # The most one mail lists; more due together go in the next.
      MOST = 25

      def self.key = :reminder

      # Worth no more than the hour it may take a household over its budget
      # to have room again, and nothing once its thing is due (its row's
      # `expires_at` says when that is, if sooner).
      def self.waits_at_most = 1.hour

      def self.account? = false

      def self.room_in?(household, now) = ReminderAllowance.new(household, now).any_left?

      # Each run of Reminders::DispatchJob queues what fell due; the drain
      # after it sends each person's together.
      def self.sends_at_once? = false

      def self.batch(row)
        OutgoingEmail.reminder.due(Time.current).where(profile_id: row.profile_id).order(:not_before, :id).limit(MOST).to_a
      end

      def message
        return unless Emails.for_reminders(profile) == :available

        due = Reminders::StillDue.new(profile, rows).to_a
        return if due.empty?

        Outgoing.new(mail: RemindersMailer.with(profile: profile, reminders: due).reminders.message, rows: due.map(&:row))
      end
    end
  end
end
