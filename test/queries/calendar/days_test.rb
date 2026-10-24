# frozen_string_literal: true

require "test_helper"

class Calendar::DaysTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
  end

  test "between draws every day of the series a profile sees, by date" do
    weekly = weekly_event(profile: @profile, type: Task, starts_on: Date.new(2025, 1, 6), title: "Bins")
    once = series!(Task, profile: @profile, starts_on: Date.new(2025, 1, 8), title: "Forms")
    series!(Task, profile: profiles(:alice), starts_on: Date.new(2025, 1, 8), title: "Someone else's")

    data = Calendar::Days.between(@profile, Date.new(2025, 1, 6), Date.new(2025, 1, 13))

    assert_equal [ Date.new(2025, 1, 6), Date.new(2025, 1, 8), Date.new(2025, 1, 13) ], data.keys.sort
    assert_equal [ once.id ], data[Date.new(2025, 1, 8)].map(&:event_id) - fixture_event_ids
    assert_equal [ weekly.id ], data[Date.new(2025, 1, 13)].map(&:event_id) - fixture_event_ids
  end

  test "a date's days from a window's series are the ones the calendar draws" do
    date = Date.new(2025, 1, 13)
    weekly_event(profile: @profile, type: Task, starts_on: Date.new(2025, 1, 6), title: "Bins")
    timed_medication!(profile: @profile, starts_on: date, times: %w[CM 20:00])

    window = Reports::Window.new(audience_for(@profile))
    from_window = Calendar::Days.on_date(window.events(date, date), date)

    assert_equal day_keys(Calendar::Days.on(@profile, date)), day_keys(from_window)
  end

  test "a date's days come with what their cards read" do
    date = Date.new(2025, 1, 13)
    weekly_event(profile: @profile, type: Task, starts_on: Date.new(2025, 1, 6), title: "Bins")
    days = Calendar::Days.on_date(Reports::Window.new(audience_for(@profile)).events(date, date), date)

    queries = count_queries { days.each { |day| [ day.event.profile, day.event.event_shares.to_a, day.event.collection ] } }

    assert_equal 0, queries
  end

  test "the cards of a week of home meals read their owner's pantry in the queries one meal's does" do
    soup = recipe_with(@profile, "Soup", [ "Leeks", 1, "kg" ])
    queries = [ [ Date.new(2025, 3, 3), 1 ], [ Date.new(2025, 3, 17), 4 ] ].map do |monday, meals|
      meals.times { |day| meal_on(@profile, monday + day, recipes: [ soup ]) }
      week = monday..(monday + 6)
      ActiveRecord::Base.uncached do
        count_queries do
          days = Calendar::Days.between(@profile, week.first, week.last)
          week.each { |date| ApplicationController.render(Views::Calendar::DayCard.new(date: date, occurrences: days[date], viewer: @profile), layout: false) }
        end
      end
    end

    assert_equal queries.first, queries.last
  end

  private

  def fixture_event_ids = Event.where(profile: @profile).where.not(title: %w[Bins Forms]).ids

  def day_keys(days) = days.map { |day| [ day.event_id, day.date, day.time_string ] }
end
