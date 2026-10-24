# frozen_string_literal: true

require "test_helper"

class Reminders::DispatchJobTest < ActiveJob::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @rome = ActiveSupport::TimeZone["Europe/Rome"]
    @alice.update!(time_zone: "Europe/Rome")
    @bob.update!(time_zone: "Europe/Rome")
  end

  test "a reminder goes out once, when its time comes on the person's clock, worded in their language" do
    @alice.update!(locale: "it")
    task = at(2026, 10, 7, 12) { task_due(Date.new(2026, 10, 9), title: "Pagare l'affitto", remind: [ 1, "days" ]) }

    assert_no_difference -> { Notification.count } do
      at(2026, 10, 8, 8, 59) { dispatch }
    end
    assert_difference -> { Notification.count } do
      at(2026, 10, 8, 9, 5) { dispatch }
      at(2026, 10, 8, 9, 10) { dispatch }
    end

    notification = Notification.last
    assert_equal [ @alice, "reminder_due", task ], [ notification.profile, notification.kind, notification.subject ]
    I18n.with_locale(:it) do
      assert_equal "Promemoria: Pagare l'affitto", wording_of(notification).title
      assert_equal "Scadenza ven 9 ott", wording_of(notification).detail
    end
    assert_equal calendar_path_for(Date.new(2026, 10, 9)), Notifications::Destination.new(notification).path
  end

  test "an appointment's reminder names its hour" do
    at(2026, 10, 7, 12) do
      appointment = Occurrences::Create.call(Appointment.new(title: "Dentist", start_time: "15:00", starts_on: Date.new(2026, 10, 9)), by: @alice)
      Events::SetReminders.call(appointment, profile: @alice, entries: [ { amount: 2, unit: "hours" } ])
    end

    at(2026, 10, 9, 13, 1) { dispatch }

    assert_equal "Due Fri 9 Oct, 15:00", wording_of(Notification.last).detail
  end

  test "a medication taken twice a day is reminded once per dose, not for one already taken" do
    event = at(2026, 10, 7, 12) do
      series = Occurrences::Create.call(Medication.new(title: "Metformin", starts_on: Date.new(2026, 10, 7), details_attributes: { kind: :pill }),
                                        by: @alice, recurrence: { frequency: "daily", slots: %w[CM 20:00] })
      Events::SetReminders.call(series, profile: @alice, entries: [ { amount: 1, unit: "hours" } ])
      series
    end

    at(2026, 10, 9, 7, 5) { dispatch }
    at(2026, 10, 9, 7, 10) { dispatch }
    assert_equal([ "Due Fri 9 Oct, 08:00" ], Notification.all.map { wording_of(_1).detail })
    assert_equal([ [ "2026-10-09", "08:00", "CM" ] ], Notification.all.map { [ _1.data["date"], _1.data["time"], _1.data["anchor"] ] })

    event.occurrence_for(Date.new(2026, 10, 9), time: "20:00").complete!
    at(2026, 10, 9, 19, 5) { dispatch }
    assert_equal 1, Notification.count, "the evening dose is already taken"

    at(2026, 10, 10, 19, 5) { dispatch }
    assert_equal([ "Due Fri 9 Oct, 08:00", "Due Sat 10 Oct, 20:00" ], Notification.order(:id).map { wording_of(_1).detail })
  end

  test "late beats never, but never once it's due" do
    at(2026, 10, 7, 12) do
      task_due(Date.new(2026, 10, 9), title: "Late", remind: [ 1, "days" ])
      task_due(Date.new(2026, 10, 8), title: "Past", remind: [ 1, "days" ])
    end

    at(2026, 10, 9, 8) { dispatch } # the laptop slept through both

    assert_equal [ "Late" ], Notification.pluck(:subject_title)
  end

  test "a reminder set after its time had passed doesn't fire" do
    at(2026, 10, 8, 12) { task_due(Date.new(2026, 10, 9), title: "Tomorrow", remind: [ 1, "days" ]) }

    at(2026, 10, 8, 12, 5) { dispatch }

    assert_equal 0, Notification.count
  end

  test "nothing about what's done, skipped or cancelled" do
    at(2026, 10, 7, 12) do
      task_due(Date.new(2026, 10, 9), title: "Done", remind: [ 1, "days" ]).first_occurrence.complete!
      task_due(Date.new(2026, 10, 9), title: "Skipped", remind: [ 1, "days" ]).first_occurrence.change_status!("skipped")
    end

    at(2026, 10, 8, 10) { dispatch }

    assert_equal 0, Notification.count
  end

  test "each occurrence of a series, from its first one" do
    at(2026, 10, 6, 12) { task_due(Date.new(2026, 10, 6), title: "Plants", remind: [ 2, "hours" ], recurrence: { frequency: "daily" }) }

    at(2026, 10, 7, 7, 5) { dispatch }
    at(2026, 10, 8, 7, 5) { dispatch }

    assert_equal(%w[2026-10-07 2026-10-08], Notification.order(:id).map { _1.data["date"] })
  end

  test "whoever it's shared with keeps their own reminders, until it's unshared" do
    task = at(2026, 10, 7, 12) do
      task_due(Date.new(2026, 10, 9), title: "Shared", remind: [ 1, "days" ]).tap do |shared|
        shared.event_shares.create!(profile: @bob)
        Events::SetReminders.call(shared, profile: @bob, entries: [ { amount: 3, unit: "hours" } ])
      end
    end

    at(2026, 10, 8, 9, 5) { dispatch }
    task.event_shares.destroy_all
    at(2026, 10, 9, 6, 5) { dispatch }

    assert_equal [ @alice ], Notification.all.map(&:profile)
  end

  test "who may still read each series is asked once per person, however many series they have reminders on" do
    at(2026, 10, 7, 12) do
      shared, * = Array.new(3) { |n| task_due(Date.new(2026, 10, 9), title: "Chore #{n}", remind: [ 1, "days" ]) }
      shared.event_shares.create!(profile: @bob)
      Events::SetReminders.call(shared, profile: @bob, entries: [ { amount: 1, unit: "days" } ])
    end

    assert_queries_match(/FROM "event_shares" WHERE "event_shares"."profile_id"/, count: 2) do
      at(2026, 10, 8, 9, 5) { dispatch }
    end
    assert_equal 4, Notification.count
  end

  test "a reminder whose notification fails isn't counted as sent, so the next run sends it" do
    at(2026, 10, 7, 12) { task_due(Date.new(2026, 10, 9), title: "Rent", remind: [ 1, "days" ]) }

    assert_error_reported(RuntimeError) do
      swapping(Notifications::Deliver, :call, ->(**) { raise "the bell is broken" }) { at(2026, 10, 8, 9, 5) { dispatch } }
    end
    assert_equal 0, EventReminderDelivery.count

    at(2026, 10, 8, 9, 10) { dispatch }
    assert_equal [ "Rent" ], Notification.pluck(:subject_title)
  end

  test "a series whose reminders fail is reported, and the others still go out" do
    at(2026, 10, 7, 12) do
      task_due(Date.new(2026, 10, 9), title: "Broken", remind: [ 1, "days" ])
      task_due(Date.new(2026, 10, 9), title: "Fine", remind: [ 1, "days" ])
    end
    due_at = Reminders::DueAt.method(:for)
    breaking = ->(occurrence, zone) { occurrence.event.title == "Broken" ? raise("a broken series") : due_at.call(occurrence, zone) }

    assert_error_reported(RuntimeError) do
      swapping(Reminders::DueAt, :for, breaking) { at(2026, 10, 8, 9, 5) { dispatch } }
    end

    assert_equal [ "Fine" ], Notification.pluck(:subject_title)
  end

  test "a lost connection fails the whole run, to be tried again" do
    at(2026, 10, 7, 12) { task_due(Date.new(2026, 10, 9), title: "Rent", remind: [ 1, "days" ]) }

    swapping(Notifications::Deliver, :call, ->(**) { raise ActiveRecord::ConnectionFailed }) { at(2026, 10, 8, 9, 5) { dispatch } }

    assert_enqueued_jobs 1, only: Reminders::DispatchJob
    assert_equal 0, EventReminderDelivery.count
  end

  private

  def at(year, month, day, hour, minute = 0, &)
    travel_to(@rome.local(year, month, day, hour, minute), &)
  end

  def dispatch = Reminders::DispatchJob.perform_now

  # The series, its reminder set.
  def task_due(date, title:, remind:, recurrence: nil)
    task = Occurrences::Create.call(Task.new(title: title, starts_on: date), by: @alice, recurrence: recurrence)
    amount, unit = remind
    Events::SetReminders.call(task, profile: @alice, entries: [ { amount: amount, unit: unit } ])
    task
  end

  def calendar_path_for(date)
    Rails.application.routes.url_helpers.calendar_path(month: date.month, year: date.year, anchor: "day_#{date.iso8601}")
  end
end
