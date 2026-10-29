# frozen_string_literal: true

require "test_helper"

class Events::SetRemindersTest < ActiveSupport::TestCase
  setup do
    @event = events(:groceries)
    @alice = profiles(:alice)
    @bob = profiles(:bob)
  end

  test "sets a person's reminders to what their form says, in minutes" do
    Events::SetReminders.call(@event, profile: @alice, entries: [ { amount: "2", unit: "days" }, { amount: "3", unit: "hours" } ])

    assert_equal [ 180, 2880 ], @event.event_reminders.for_profile(@alice).order(:offset_minutes).pluck(:offset_minutes)
    assert_equal [ [ 3, "hours" ], [ 2, "days" ] ], @event.event_reminders.order(:offset_minutes).map(&:amount_and_unit)
  end

  test "keeps the ones that stay, drops the ones removed, and leaves other people's alone" do
    kept = @event.event_reminders.create!(profile: @alice, offset_minutes: 60)
    @event.event_reminders.create!(profile: @alice, offset_minutes: 1440)
    bobs = @event.event_reminders.create!(profile: @bob, offset_minutes: 1440)

    Events::SetReminders.call(@event, profile: @alice, entries: [ { amount: "1", unit: "hours" } ])

    assert_equal [ kept, bobs ].sort, @event.event_reminders.reload.sort
  end

  test "what can't be a reminder is dropped, repeats too, and five is the most" do
    entries = [
      { amount: "", unit: "days" }, { amount: "0", unit: "hours" }, { amount: "31", unit: "days" }, { amount: "2", unit: "weeks" },
      { amount: "abc", unit: "hours" }, { amount: "24", unit: "hours" }, { amount: "1", unit: "days" },
      *(2..7).map { { amount: _1.to_s, unit: "hours" } }
    ]

    Events::SetReminders.call(@event, profile: @alice, entries: entries)

    assert_equal [ 120, 180, 240, 300, 1440 ], @event.event_reminders.order(:offset_minutes).pluck(:offset_minutes)
  end

  test "a row with the box says whether its reminder comes by email; one drawn without it leaves a staying reminder as it was" do
    by_mail = @event.event_reminders.create!(profile: @alice, offset_minutes: 60, by_email: true)
    to_mail = @event.event_reminders.create!(profile: @alice, offset_minutes: 120)

    Events::SetReminders.call(@event, profile: @alice, entries: [ { amount: "1", unit: "hours", by_email: "0" }, { amount: "2", unit: "hours", by_email: "1" } ])
    assert_equal [ [ by_mail.id, false ], [ to_mail.id, true ] ], @event.event_reminders.order(:offset_minutes).pluck(:id, :by_email)

    Events::SetReminders.call(@event, profile: @alice, entries: [ { amount: "1", unit: "hours" }, { amount: "2", unit: "hours" }, { amount: "3", unit: "hours" } ])
    assert_equal [ false, true, false ], @event.event_reminders.order(:offset_minutes).pluck(:by_email), "a new one is the bell's alone"
  end

  test "a reminder asked for twice comes by email if either row asks" do
    Events::SetReminders.call(@event, profile: @alice, entries: [ { amount: "1", unit: "days", by_email: "0" }, { amount: "24", unit: "hours", by_email: "1" } ])

    assert_equal [ [ 1440, true ] ], @event.event_reminders.pluck(:offset_minutes, :by_email)
  end

  test "an empty form removes them all" do
    @event.event_reminders.create!(profile: @alice, offset_minutes: 60)

    Events::SetReminders.call(@event, profile: @alice, entries: [])

    assert_empty @event.event_reminders.reload
  end
end
