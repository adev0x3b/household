# frozen_string_literal: true

require "test_helper"

class Reports::HomeTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.current
  end

  test "one dashboard per section of the household" do
    assert_equal(
      [ Reports::Agenda::Dashboard, Reports::Healthcare::Dashboard, Reports::Finance::Dashboard, Reports::Pantry::Dashboard ],
      [ dashboard.agenda, dashboard.healthcare, dashboard.finance, dashboard.pantry ].map(&:class),
    )
  end

  test "attention merges every section's items, urgent first, then the nearest to today" do
    task!(profile: @profile, date: @today - 1, priority: :low)
    medication!(profile: @profile, date: @today - 2)
    expense!(profile: @profile, date: @today - 3, cents: 500, status: :pending)

    kinds = dashboard.attention.map { |item| [ item.kind, item.severity ] }

    assert_equal [ [ :missed_dose, :critical ], [ :overdue_task, :warning ], [ :overdue_transaction, :warning ] ], kinds
  end

  test "healthcare and finance report on the last 30 days unless a period is picked" do
    expense!(profile: @profile, date: @today - 29, cents: 500)
    expense!(profile: @profile, date: @today - 30, cents: 700)

    assert_equal [ @today - 29, @today ], [ dashboard.period.start_date, dashboard.period.end_date ]
    assert_equal [ 500, 500 ], [ dashboard.healthcare.spending.spend_metric.value.cents, dashboard.finance.spending.total_metric.value.cents ]

    sixty_days = period(@today - 59, @today)
    picked = Reports::Home.new(audience: audience_for(@profile), period: sixty_days, today: @today)

    assert_equal [ 1200, 1200 ], [ picked.healthcare.spending.spend_metric.value.cents, picked.finance.spending.total_metric.value.cents ]
  end

  test "attention items say which day to open: saved, or projected on a repeating series" do
    task = task!(profile: @profile, date: @today - 1)
    series = weekly_event(profile: @profile, type: Medication, starts_on: @today - 9)
    medication!(profile: @profile, event: series, date: @today - 9, status: :completed)

    days = dashboard.attention.to_h { |item| [ item.kind, item.occurrence ] }

    assert_equal task, days[:overdue_task]
    assert_equal [ series, @today - 2, true ], [ days[:missed_dose].event, days[:missed_dose].date, days[:missed_dose].projected? ]
  end

  test "the next 7 days list what's still to do, by day, without today" do
    task!(profile: @profile, date: @today, title: "Today")
    task!(profile: @profile, date: @today + 1, title: "Low", priority: :low)
    task!(profile: @profile, date: @today + 1, title: "Urgent", priority: :urgent)
    task!(profile: @profile, date: @today + 1, title: "Done", status: :completed)
    task!(profile: @profile, date: @today + 3, title: "Later")
    task!(profile: @profile, date: @today + 8, title: "Too far")
    task!(profile: profiles(:alice), date: @today + 1, title: "Not mine")

    days = dashboard.upcoming.days

    assert_equal [ @today + 1, @today + 3 ], days.map(&:date)
    assert_equal([ %w[Urgent Low], %w[Later] ], days.map { |day| day.items.map(&:label) })
    assert_equal 1, dashboard.upcoming.page.total_pages
  end

  test "the next 7 days mix every kind, a projected day included, timed ones first within a day" do
    weekly_event(profile: @profile, type: Task, starts_on: @today - 6, title: "Bins")
    appointment!(profile: @profile, date: @today + 2, kind: :social, title: "Dinner", start_time: "20:00")
    meal_on(@profile, @today + 2, title: "Soup", meal_type: :lunch)

    items = dashboard.upcoming.days.flat_map(&:items)

    assert_equal([ [ Task, "Bins", @today + 1, true ], [ Appointment, "Dinner", @today + 2, false ], [ Meal, "Soup", @today + 2, false ] ],
                 items.map { |item| [ item.type, item.label, item.date, item.occurrence.projected? ] })
  end

  test "the next 7 days come a page at a time, a day running on to the next page, a page too far showing the last" do
    (Reports::Upcoming::PER_PAGE + 2).times { |index| task!(profile: @profile, date: @today + 1, title: format("Task %02d", index)) }
    task!(profile: @profile, date: @today + 2, title: "Later")

    first = dashboard.upcoming
    second = Reports::Home.new(audience: audience_for(@profile), today: @today, upcoming_page: "2").upcoming
    beyond = Reports::Home.new(audience: audience_for(@profile), today: @today, upcoming_page: "9").upcoming

    assert_equal [ 2, Reports::Upcoming::PER_PAGE ], [ first.page.total_pages, first.days.sum { |day| day.items.size } ]
    assert_equal([ [ @today + 1, 2 ], [ @today + 2, 1 ] ], second.days.map { |day| [ day.date, day.items.size ] })
    assert_equal [ 2, second.days.flat_map(&:items).map(&:label) ], [ beyond.page.current_page, beyond.days.flat_map(&:items).map(&:label) ]
  end

  test "the next 7 days list each dose of a day with its time, in clock order" do
    record = timed_medication!(profile: @profile, starts_on: @today, times: %w[CV 08:00], name: "Metformin")
    record.event.occurrence_for(@today + 1, time: "08:00").complete!

    day = dashboard.upcoming.days.first

    assert_equal @today + 1, day.date
    assert_equal([ [ "Metformin", "19:30", "CV" ] ], day.items.map { |item| [ item.label, item.time, item.anchor ] })
    assert_equal [ "08:00", "19:30" ], dashboard.upcoming.days.second.items.map(&:time)
  end

  private

  def dashboard
    @dashboard ||= Reports::Home.new(audience: audience_for(@profile), today: @today)
  end
end
