# frozen_string_literal: true

require "test_helper"

# Which reminder mails in the outbox are still worth sending, read from the
# series as they are when the mail's turn comes.
class Reminders::StillDueTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @alice.update!(time_zone: "Europe/Rome")
    @rome = @alice.zone
    @rent = series!("Task", profile: @alice, starts_on: Date.new(2026, 10, 9), title: "Rent")
    @pills = series!("Medication", profile: @alice, starts_on: Date.new(2026, 10, 1), title: "Pills", rrule: "FREQ=DAILY", slots: %w[08:00 20:00])
    @rent_reminder = reminder(@rent)
    @pills_reminder = reminder(@pills)
  end

  test "what each row reminds of and when it is due, soonest first" do
    rows = [ row(@rent_reminder, "2026-10-09"), row(@pills_reminder, "2026-10-09", "08:00"), row(@pills_reminder, "2026-10-08", "20:00") ]

    due = at(2026, 10, 8, 10) { still_due(rows) }

    assert_equal [ rows[2], rows[1], rows[0] ], due.map(&:row)
    assert_equal([ [ "Pills", "20:00" ], [ "Pills", "08:00" ], [ "Rent", nil ] ], due.map { [ _1.occurrence.event.title, _1.occurrence.time_string ] })
    assert_equal [ @rome.local(2026, 10, 8, 20), @rome.local(2026, 10, 9, 8), @rome.local(2026, 10, 9, 9) ], due.map(&:due_at)
    assert_equal [ true, true, false ], due.map(&:timed)
  end

  test "leaves out a row whose reminder is gone, back to the bell or someone else's, and one whose series the person may no longer read" do
    gone = row(reminder(@rent, offset_minutes: 120).tap(&:destroy!), "2026-10-09")
    bell = row(reminder(@rent, offset_minutes: 180).tap { _1.update!(by_email: false) }, "2026-10-09")
    bobs_series = series!("Task", profile: profiles(:bob), starts_on: Date.new(2026, 10, 9), title: "Bob's").tap { _1.event_shares.create!(profile: @alice) }
    bobs = row(reminder(bobs_series, profile: profiles(:bob)), "2026-10-09")
    unshared = row(reminder(bobs_series), "2026-10-09")
    bobs_series.event_shares.destroy_all
    kept = row(@rent_reminder, "2026-10-09")

    assert_equal [ kept ], at(2026, 10, 8, 10) { still_due([ gone, bell, bobs, unshared, kept ]) }.map(&:row)
  end

  test "leaves out a day done, deleted, moved or at a time no longer the series', and a thing already due" do
    @pills.occurrence_on(Date.new(2026, 10, 9), time: "08:00").complete!
    Occurrences::Destroy.call(@pills.occurrence_on(Date.new(2026, 10, 10), time: "08:00"), by: @alice)
    moved = series!("Task", profile: @alice, starts_on: Date.new(2026, 10, 9), title: "Moved").tap { _1.update!(starts_on: Date.new(2026, 10, 12)) }
    rows = [
      row(@pills_reminder, "2026-10-09", "08:00"), row(@pills_reminder, "2026-10-10", "08:00"), row(reminder(moved), "2026-10-09"),
      row(@pills_reminder, "2026-10-09", "12:00"), row(@pills_reminder, "2026-10-08", "08:00")
    ]
    kept = row(@pills_reminder, "2026-10-09", "20:00")

    assert_equal [ kept ], at(2026, 10, 8, 10) { still_due([ *rows, kept ]) }.map(&:row)
  end

  test "reads the reminders, the series and their days once for every row" do
    rows = [ row(@rent_reminder, "2026-10-09"), *(1..9).map { row(@pills_reminder, "2026-10-#{10 + _1}", "08:00") } ]

    assert_queries_match(/FROM "event_reminders"/, count: 1) do
      assert_queries_match(/FROM "occurrences"/, count: 1) { assert_equal 10, at(2026, 10, 8, 10) { still_due(rows) }.size }
    end
  end

  private

  def reminder(event, profile: @alice, offset_minutes: 60) = event.event_reminders.create!(profile: profile, offset_minutes: offset_minutes, by_email: true)

  def row(reminder, date, time = nil)
    OutgoingEmail.new(profile: @alice, kind: :reminder, data: { "event_reminder_id" => reminder.id, "date" => date, "time" => time }.compact)
  end

  def still_due(rows) = Reminders::StillDue.new(@alice, rows).to_a

  def at(*moment, &) = travel_to(@rome.local(*moment), &)
end
