# frozen_string_literal: true

require "test_helper"

class Reports::WindowTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 1, 20)
    @window = Reports::Window.new(audience_for(@profile))
  end

  test "loads the covered span once, at the first ask: later ledgers inside it read memory" do
    weekly_event(profile: @profile, type: Medication, starts_on: Date.new(2025, 1, 6))
    weekly_event(profile: @profile, type: Task, starts_on: Date.new(2025, 1, 7), title: "Bins")

    assert_equal 0, count_queries { @window.cover(Date.new(2025, 1, 1), Date.new(2025, 1, 31)) }, "covering loads nothing yet"
    first_half = @window.ledger(period(Date.new(2025, 1, 1), Date.new(2025, 1, 15)), today: @today).entries

    doses = nil
    queries = count_queries do
      doses = @window.ledger(period(Date.new(2025, 1, 10), Date.new(2025, 1, 31)), today: @today, of: Medication).entries
      @window.ledger(period(Date.new(2025, 1, 1), Date.new(2025, 1, 31)), today: @today, of: Task).entries
    end

    assert_equal [ 6, 7, 13, 14 ], first_half.map { _1.date.day }.sort
    assert_equal([ 13, 20, 27 ], doses.map { _1.date.day })
    assert_equal 0, queries
  end

  test "loads only the kinds asked for, each once" do
    medication = weekly_event(profile: @profile, type: Medication, starts_on: Date.new(2025, 1, 6))
    task = weekly_event(profile: @profile, type: Task, starts_on: Date.new(2025, 1, 7), title: "Bins")
    january = [ Date.new(2025, 1, 1), Date.new(2025, 1, 31) ]

    assert_equal [ task ], @window.events(*january, of: Task)
    assert_operator count_queries { @window.events(*january, of: Medication) }, :>, 0, "a kind not asked for yet is loaded"
    assert_equal(0, count_queries { assert_equal [ task, medication ], @window.events(*january, of: [ Task, Medication ]) })
  end

  test "a period outside the span widens it, loading once more" do
    weekly_event(profile: @profile, type: Task, starts_on: Date.new(2025, 1, 7), title: "Bins")
    @window.cover(Date.new(2025, 1, 1), Date.new(2025, 1, 31))

    february = period(Date.new(2025, 2, 1), Date.new(2025, 2, 28))
    assert_equal 4, @window.ledger(february, today: @today).entries.size

    queries = count_queries do
      @window.ledger(period(Date.new(2025, 1, 20), Date.new(2025, 2, 10)), today: @today).entries
    end
    assert_equal 0, queries, "January and February are both covered now"
  end

  test "holds the series with a day in the span, and only those" do
    inside = series!(Task, profile: @profile, starts_on: Date.new(2025, 1, 9), title: "Dentist forms")
    series!(Task, profile: @profile, starts_on: Date.new(2025, 3, 2), title: "Taxes")
    weekly = weekly_event(profile: @profile, type: Task, starts_on: Date.new(2024, 12, 2), title: "Bins")

    assert_equal [ inside, weekly ].map(&:id).sort, @window.events(Date.new(2025, 1, 1), Date.new(2025, 1, 31)).map(&:id).sort
  end
end
