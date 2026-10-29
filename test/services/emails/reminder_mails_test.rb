# frozen_string_literal: true

require "test_helper"

# Reminders by email, from the run that finds them due to the drain that
# sends them: each person's together, within their household's budget,
# and only while they are still wanted.
class Emails::ReminderMailsTest < ActiveSupport::TestCase
  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
    [ @alice, @bob ].each { _1.update!(time_zone: "Europe/Rome", email_confirmed_at: 1.day.ago) }
    @rome = @alice.zone
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = ActiveSupport::Cache::NullStore.new }

  test "the reminders a run finds due go out at the next minute's drain, one mail for each person's" do
    at(10, 7, 12) do
      remind(@alice, task(@alice, "Rent", Date.new(2026, 10, 9)))
      remind(@alice, series!("Medication", profile: @alice, starts_on: Date.new(2026, 10, 9), title: "Methotrexate", slots: %w[08:00]), hours: 25)
      remind(@bob, task(@bob, "Bins", Date.new(2026, 10, 9)))
    end

    mails = at(10, 8, 9, 5) do
      dispatch
      assert_empty drain, "not before the minute that gathers them"
      travel Emails::Enqueue::GATHER
      drain
    end

    assert_equal [ [ "alice@example.com" ], [ "bob@example.com" ] ], mails.map(&:to).sort
    alices = mails.find { _1.to == [ "alice@example.com" ] }
    assert_equal "2 reminders from Household", alices.subject
    assert_match(/Your medication, at 08:00 on Friday 9 October\n- Your task “Rent”, on Friday 9 October/, alices.text_part.body.to_s)
    assert_not_includes alices.text_part.body.to_s, "Methotrexate"
    assert_equal 2, OutgoingEmail.sent.distinct.count(:message_id)
    assert_equal [ {} ], OutgoingEmail.distinct.pluck(:data), "a sent row keeps nothing of what it reminded of"
  end

  test "dropped at its turn: a reminder no longer asked for by email, and mail to an address no longer confirmed" do
    at(10, 7, 12) do
      remind(@alice, task(@alice, "Rent", Date.new(2026, 10, 9)))
      remind(@bob, task(@bob, "Bins", Date.new(2026, 10, 9)))
    end
    at(10, 8, 9, 5) { dispatch }

    Reminders::StopEmail.call(@alice)
    @bob.update!(email_confirmed_at: nil)

    assert_empty at(10, 8, 9, 10) { drain }
    assert_equal [ "dropped" ] * 2, OutgoingEmail.pluck(:status)
  end

  test "a household gets no more reminder mails a day than its budget; the rest wait their hour, then fail" do
    profiles(:outsider).update!(time_zone: "Europe/Rome", email_confirmed_at: 1.day.ago)
    at(10, 7, 12) do
      remind(@alice, task(@alice, "Rent", Date.new(2026, 10, 9)))
      remind(@bob, task(@bob, "Bins", Date.new(2026, 10, 9)))
      remind(profiles(:outsider), task(profiles(:outsider), "Elsewhere", Date.new(2026, 10, 9)))
    end
    at(10, 8, 9, 5) { dispatch }

    sent = at(10, 8, 9, 10) { drain("REMINDER_MAILS_PER_DAY" => "1") }

    assert_equal 2, sent.size, "one of the household's, and the other household's"
    held = OutgoingEmail.queued.sole
    assert_equal [ "over_budget", @rome.local(2026, 10, 8, 9, 25) ], [ held.reason, held.not_before ]

    at(10, 8, 10, 6) { drain("REMINDER_MAILS_PER_DAY" => "1") }
    assert_equal [ "failed", "over_budget" ], [ held.reload.status, held.reason ]
  end

  private

  def at(month, day, hour, minute = 0, &) = travel_to(@rome.local(2026, month, day, hour, minute), &)

  def task(profile, title, date) = Occurrences::Create.call(Task.new(title: title, starts_on: date), by: profile)

  # A day before, unless told otherwise, by email too.
  def remind(profile, event, hours: 24)
    Events::SetReminders.call(event, profile: profile, entries: [ { amount: hours, unit: "hours", by_email: "1" } ])
  end

  def dispatch = with_relay { Reminders::DispatchJob.perform_now }

  def drain(relay = {}) = with_relay(relay) { relayed { Emails::Drain.call } }
end
