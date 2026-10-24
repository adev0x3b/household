# frozen_string_literal: true

require "test_helper"

# A card pushed to someone's calendar is theirs: their language, their
# today — not the one of whoever made the change.
class Calendar::DayCardBroadcasterTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  teardown { travel_back }

  test "rendered in the recipient's language and on their clock, whoever edited" do
    bob = profiles(:bob).tap { _1.update!(locale: "it", time_zone: "Europe/Rome") }
    task = task!(profile: profiles(:alice), date: Date.new(2026, 10, 15), title: "Water the plants")
    task.event.event_shares.create!(profile: bob)
    travel_to Time.utc(2026, 10, 14, 22, 30) # past midnight in Rome, still the 14th in UTC

    CalendarWatch.watch!("profile_#{bob.id}:2026-10", "bob's tab") # Bob has October open

    pushed = capture_broadcasts("profile_#{bob.id}:2026-10") do
      I18n.with_locale(:en) { Time.use_zone("UTC") { Calendar::DayCardBroadcaster.call(event: task.event) } }
    end.join

    assert_includes pushed, I18n.l(task.date, format: :day_long, locale: :it)
    assert_not_includes pushed, I18n.l(task.date, format: :day_long, locale: :en)
    assert_match(/day-card--today/, pushed, "the 15th is bob's today")
  end

  test "a day shown with the month beside it is pushed to that month's room, marked as beside it" do
    alice = profiles(:alice)
    task = task!(profile: alice, date: Date.new(2026, 9, 30), title: "Last of September")
    CalendarWatch.watch!("profile_#{alice.id}:2026-10", "alice's tab") # October shows Mon 28 Sep onwards

    pushed = capture_broadcasts("profile_#{alice.id}:2026-10") { Calendar::DayCardBroadcaster.call(event: task.event) }

    assert_equal 1, pushed.size
    assert_includes pushed.first, %(target="day_2026-09-30")
    assert_includes pushed.first, "day-card--beside"
  end

  test "a day moved off a month's page is redrawn there, in the room of the month showing it" do
    alice = profiles(:alice)
    task = task!(profile: alice, date: Date.new(2026, 11, 20), title: "Moved")
    CalendarWatch.watch!("profile_#{alice.id}:2026-10", "alice's tab")

    pushed = capture_broadcasts("profile_#{alice.id}:2026-10") do
      Calendar::DayCardBroadcaster.call(event: task.event, dates: [ Date.new(2026, 11, 1) ])
    end

    assert_equal 1, pushed.size, "the 1st of November is on October's page; the 20th isn't"
    assert_includes pushed.first, %(target="day_2026-11-01")
  end

  test "a series with a day on every date of the page is redrawn in as many queries as a weekly one" do
    alice = profiles(:alice)
    weekly, daily = %w[WEEKLY DAILY].map do |frequency|
      series!("Task", profile: alice, starts_on: Date.new(2026, 9, 1), title: frequency, rrule: "FREQ=#{frequency}")
    end
    CalendarWatch.watch!("profile_#{alice.id}:2026-10", "alice's tab")

    # Uncached: both redraw the same page for the same person, so the second
    # would find the first's reads in the query cache.
    queries = [ daily, weekly ].map do |event|
      ActiveRecord::Base.uncached { count_queries { Calendar::DayCardBroadcaster.call(event: event) } }
    end

    assert_equal queries.first, queries.last
  end

  test "a month nobody has open is not rendered" do
    task = task!(profile: profiles(:alice), date: Date.new(2026, 10, 15), title: "Water the plants")

    assert_no_broadcasts("profile_#{profiles(:alice).id}:2026-10") { Calendar::DayCardBroadcaster.call(event: task.event) }
  end
end
