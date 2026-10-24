# frozen_string_literal: true

require "test_helper"

class Reports::Agenda::AttentionItemsTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 3, 15)
  end

  test "high and urgent tasks need attention urgently, a day's own priority first" do
    task!(profile: @profile, date: @today - 5, priority: :low, title: "Dust")
    task!(profile: @profile, date: @today - 2, priority: :urgent, title: "Boiler")
    task!(profile: @profile, date: @today - 20, priority: :high, title: "Old")
    bins = weekly_event(profile: @profile, type: Task, starts_on: @today - 7, title: "Bins", priority: :low)
    day!(bins, date: @today - 7).write_details!(priority: :urgent)

    assert_equal [ [ "Bins", :critical ], [ "Boiler", :critical ], [ "Dust", :warning ], [ "Old", :critical ] ],
                 attention.map { |item| [ item.subject, item.severity ] }.sort
  end

  test "every task passed and still to do needs attention, however long ago, once a series: its newest day, counting the rest" do
    task!(profile: @profile, date: @today - 8, title: "Phone refund")
    task!(profile: @profile, date: @today - 400, title: "Forgotten", status: :in_progress)
    task!(profile: @profile, date: @today - 3, title: "Done", status: :completed)
    task!(profile: @profile, date: @today - 3, title: "Skipped", status: :skipped)
    task!(profile: @profile, date: @today - 3, title: "Called off", status: :cancelled)
    bins = weekly_event(profile: @profile, type: Task, starts_on: @today - 21, title: "Bins") # -21, -14, -7, today
    day!(bins, date: @today - 14, status: :completed)

    assert_equal [ [ "Bins", @today - 7, 2 ], [ "Forgotten", @today - 400, 1 ], [ "Phone refund", @today - 8, 1 ] ],
                 attention.map { [ _1.subject, _1.date, _1.count ] }.sort
  end

  test "the agenda's own appointments passed and still pending need their outcome recorded; a visit is Healthcare's" do
    appointment!(profile: @profile, date: @today - 60, title: "Dinner with Marta", kind: :social)
    appointment!(profile: @profile, date: @today - 2, title: "Dentist", kind: :medical)

    assert_equal([ [ :appointment_outcome, "Dinner with Marta" ] ], attention.map { [ _1.kind, _1.subject ] })
  end

  private

  def attention
    Reports::Agenda::Dashboard.new(audience: audience_for(@profile), period: Reports::Period.recent(today: @today), today: @today).attention.to_a
  end
end
