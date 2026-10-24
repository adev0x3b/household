# frozen_string_literal: true

require "test_helper"

class Reports::Healthcare::AttentionItemsTest < ActiveSupport::TestCase
  test "lists recent missed doses and past visits without an outcome, critical first" do
    profile = profiles(:carol)
    today = Date.current
    medication!(profile: profile, date: today - 2)
    appointment!(profile: profile, date: today - 5)
    appointment!(profile: profile, date: today - 4, kind: :work, title: "Interview")

    dashboard = Reports::Healthcare::Dashboard.new(audience: audience_for(profile), period: period(today.beginning_of_year, today), today: today)
    kinds = dashboard.attention.map { |item| [ item.kind, item.severity, item.subject ] }

    assert_equal [ [ :missed_dose, :critical, "Cobalamin" ], [ :appointment_outcome, :warning, "Checkup" ] ], kinds,
                 "an appointment that isn't medical belongs to the Agenda"
  end

  test "a dose missed, a visit unrecorded or a lab test pending needs attention however long ago; one taken, cancelled or skipped doesn't" do
    profile = profiles(:carol)
    today = Date.new(2026, 10, 9)
    medication!(profile: profile, date: today - 300, name: "Old dose")
    medication!(profile: profile, date: today - 3, name: "Taken", status: :completed)
    appointment!(profile: profile, date: today - 120, title: "Cardiology")
    appointment!(profile: profile, date: today - 10, title: "Called off", status: :cancelled)
    lab_result!(profile: profile, date: today - 45, title: "Blood panel")

    items = attention(profile, today, Time.current).map { |item| [ item.kind, item.subject, item.date ] }

    assert_equal [ [ :appointment_outcome, "Cardiology", today - 120 ], [ :missed_dose, "Old dose", today - 300 ], [ :pending_lab_result, "Blood panel", today - 45 ] ],
                 items.sort
  end

  test "an item says which day it is about, so the page opens it in place" do
    profile = profiles(:carol)
    today = Date.new(2026, 10, 9)
    series = weekly_event(profile: profile, type: Medication, starts_on: today - 9) # Wednesdays: today - 9, today - 2
    medication!(profile: profile, event: series, date: today - 9, status: :completed)

    item = attention(profile, today, Time.current).find { |i| i.kind == :missed_dose }

    assert_equal [ series, today - 2 ], [ item.occurrence.event, item.occurrence.date ]
    assert_predicate item.occurrence, :projected?
  end

  test "a dose due today at a set time is overdue once its time and grace have passed, on the viewer's clock" do
    profile = profiles(:carol)
    profile.update!(time_zone: "Europe/Rome")
    today = Date.new(2026, 10, 9)
    twice = timed_medication!(profile: profile, starts_on: today - 10, times: %w[08:00 20:00], name: "Metformin")
    timed_medication!(profile: profile, starts_on: today - 10, times: %w[CM], name: "Levothyroxine")
    rome = ActiveSupport::TimeZone["Europe/Rome"]

    kinds = ->(now) { attention(profile, today, now).select { |item| item.kind == :overdue_dose }.map { |item| [ item.subject, item.occurrence.time_string ] } }

    assert_equal [], kinds.call(rome.local(2026, 10, 9, 8, 59)), "both due at 08:00, within the grace"
    assert_equal [ [ "Metformin", "08:00" ] ], kinds.call(rome.local(2026, 10, 9, 9, 0)), "an hour's grace with several a day"
    assert_equal [ [ "Levothyroxine", "08:00" ], [ "Metformin", "08:00" ] ], kinds.call(rome.local(2026, 10, 9, 10, 0)).sort, "two hours' with one"
    assert_equal [ [ "Levothyroxine", "08:00" ], [ "Metformin", "08:00" ], [ "Metformin", "20:00" ] ], kinds.call(rome.local(2026, 10, 9, 21, 30)).sort

    twice.event.occurrence_for(today, time: "08:00").complete!
    assert_equal [ [ "Levothyroxine", "08:00" ] ], kinds.call(rome.local(2026, 10, 9, 10, 0))

    item = attention(profile, today, rome.local(2026, 10, 9, 21, 30)).find { |i| i.kind == :overdue_dose && i.subject == "Metformin" }
    occurrence = item.occurrence
    assert_equal [ today, "20:00", nil, true ], [ item.date, occurrence.time_string, occurrence.anchor, occurrence.projected? ]
    assert_equal twice.event, occurrence.event
  end

  test "a dose skipped because it wasn't there or was forgotten needs attention; a refusal is a decision" do
    profile = profiles(:carol)
    today = Date.new(2026, 10, 9)
    record = timed_medication!(profile: profile, starts_on: today - 10, times: %w[CM CV])
    record.event.occurrence_for(today - 1, time: "08:00").change_status!("skipped", reason: "forgot")
    record.event.occurrence_for(today - 1, time: "19:30").change_status!("skipped", reason: "refused")
    record.event.occurrence_for(today - 2, time: "08:00").change_status!("skipped", reason: "not_available")
    record.event.occurrence_for(today - 9, time: "08:00").change_status!("skipped", reason: "forgot")

    items = attention(profile, today, Time.current).select { |item| item.kind == :skipped_dose }

    assert_equal([ [ today - 1, "forgot" ], [ today - 2, "not_available" ] ], items.map { |item| [ item.date, item.occurrence.skipped_reason ] })
    assert(items.all? { |item| item.severity == :warning })
  end

  test "a critical lab value opens the lab report's day" do
    profile = profiles(:carol)
    analytes(:glucose).update!(profile: profile)
    today = Date.new(2026, 10, 9)
    report = series!("LabTestResult", profile: profile, starts_on: today - 3, title: "Bloods")
    day = day!(report, date: today - 3, status: :completed)
    LabTestResultEntry.create!(occurrence: day, analyte: analytes(:glucose), unit: units(:mgdl), value: "300")

    item = attention(profile, today, Time.current).find { |i| i.kind == :critical_lab_value }

    assert_equal [ "Glucose", today - 3, day ], [ item.subject, item.date, item.occurrence ]
  end

  private

  def attention(profile, today, now)
    Reports::Healthcare::Dashboard.new(audience: audience_for(profile), period: period(today.beginning_of_year, today), today: today, now: now).attention
  end
end
