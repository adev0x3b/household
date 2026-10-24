# frozen_string_literal: true

require "test_helper"

class Reports::Healthcare::MedicationsTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 2, 20)
    @february = period(Date.new(2025, 2, 1), Date.new(2025, 2, 28))
    @event = weekly_event(profile: @profile, type: Medication, starts_on: Date.new(2025, 1, 6), title: "Cobalamin") # Mondays
  end

  test "adherence compares with the previous period and carries the 80% target" do
    # Previous period (Jan 4 – Jan 31): 6, 13, 20, 27 → 2 of 4 taken.
    [ 6, 13 ].each { |day| taken(Date.new(2025, 1, day)) }
    # February up to the 20th: 3, 10, 17 → 3 of 3 taken.
    [ 3, 10, 17 ].each { |day| taken(Date.new(2025, 2, day)) }

    metric = report.adherence_metric

    assert_in_delta 100.0, metric.value
    assert_in_delta 50.0, metric.previous
    assert_equal 80, metric.target
    assert_equal :improving, metric.trend
  end

  test "missed doses count missed and skipped" do
    taken(Date.new(2025, 2, 3))
    medication!(profile: @profile, event: @event, date: Date.new(2025, 2, 10), status: :skipped)
    # 17th: nothing saved → missed. 24th: future.

    assert_equal 2, report.missed_metric.value
  end

  test "timing histogram clamps to ±3 days" do
    medication!(profile: @profile, event: @event, date: Date.new(2025, 2, 3), status: :completed, completed_on: Date.new(2025, 2, 3))
    medication!(profile: @profile, event: @event, date: Date.new(2025, 2, 10), status: :completed, completed_on: Date.new(2025, 2, 16))

    values = report.timing_chart.series.first.values

    assert_equal [ 1, 0, 0, 1, 0, 0, 0 ], values # [3+ late, 2 late, 1 late, on time, 1 early, 2 early, 3+ early]
  end

  test "rows show worst adherence first, with the streak and the next dose" do
    taken(Date.new(2025, 2, 10))
    taken(Date.new(2025, 2, 17))

    row = report.rows.first

    assert_equal "Cobalamin", row.name
    assert_equal 2, row.streak
    assert_equal Date.new(2025, 2, 24), row.next_date
  end

  test "past the period, the next dose is the schedule's next date not deleted from it" do
    taken(Date.new(2025, 1, 27))
    @event.skip!(Date.new(2025, 2, 24))
    january = period(Date.new(2025, 1, 1), Date.new(2025, 1, 31))

    row = Reports::Healthcare::Medications.new(audience: audience_for(@profile), period: january, today: @today).rows.sole

    assert_equal Date.new(2025, 3, 3), row.next_date, "the first Monday after today (the 20th), the 24th being deleted"
  end

  test "a medication of a collection shared with the viewer counts; a stranger's doesn't" do
    therapy = Collection.create!(profile: profiles(:bob), name: "B12")
    CollectionShare.create!(collection: therapy, profile: @profile)
    shared = series!("Medication", profile: profiles(:bob), starts_on: Date.new(2025, 2, 3), title: "Folic acid", collection: therapy)
    day!(shared, date: Date.new(2025, 2, 3), status: :completed)
    series!("Medication", profile: profiles(:alice), starts_on: Date.new(2025, 2, 3), title: "Not mine")

    assert_equal [ "Cobalamin", "Folic acid" ], report.rows.map(&:name).sort
  end

  test "adherence counts every dose of a day" do
    record = timed_medication!(profile: @profile, starts_on: Date.new(2025, 2, 18), times: %w[08:00 20:00], name: "Amoxicillin")
    record.complete!
    record.event.occurrence_for(Date.new(2025, 2, 19), time: "20:00").complete!
    # 18th: 08:00 taken, 20:00 missed; 19th: 08:00 missed, 20:00 taken; 20th: today; later: upcoming.

    row = report.rows.find { |r| r.name == "Amoxicillin" }
    # Every dose is its own day.

    assert_equal [ 4, 2, 50.0 ], [ row.due, row.taken, row.rate ]
  end

  private

  def taken(date)
    medication!(profile: @profile, event: @event, date: date, status: :completed, completed_on: date)
  end

  def report
    Reports::Healthcare::Medications.new(audience: audience_for(@profile), period: @february, today: @today)
  end
end
