# frozen_string_literal: true

require "test_helper"

# How many reminder mails a household's people may still have today: every
# person's together, a mail of several reminders counted once.
class Emails::ReminderAllowanceTest < ActiveSupport::TestCase
  def mailed(profile, at:, message_id: SecureRandom.uuid, status: :sent, kind: :reminder)
    OutgoingEmail.create!(profile:, kind:, status:, message_id:, claimed_at: at, not_before: at, expires_at: at)
  end

  test "counts the reminder mails taken to go to the household's people in the rolling day" do
    freeze_time
    with_env("REMINDER_MAILS_PER_DAY" => "2") do
      2.times { mailed(profiles(:alice), at: 2.hours.ago, message_id: "two-reminders@household.example") }
      mailed(profiles(:bob), at: 25.hours.ago)
      mailed(profiles(:outsider), at: 1.hour.ago)
      mailed(profiles(:carol), at: 1.hour.ago, kind: :test_mail)
      assert_predicate Emails::ReminderAllowance.new(households(:example)), :any_left?

      mailed(profiles(:bob), at: 1.hour.ago, status: :failed)
      assert_not Emails::ReminderAllowance.new(households(:example)).any_left?, "a refused mail counts"
      assert_predicate Emails::ReminderAllowance.new(households(:example), 23.hours.from_now), :any_left?
    end
  end
end
