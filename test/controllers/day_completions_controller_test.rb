# frozen_string_literal: true

require "test_helper"

# A day's completion, put there or taken away by the circle on its card.
class DayCompletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
  end

  test "marking a day nothing was stored about done stores it; taking the completion away reopens it" do
    event = events(:water_the_plants)

    post event_day_completion_path(event, "2026-03-23"), as: :turbo_stream
    assert_response :success
    day = event.occurrence_on(Date.new(2026, 3, 23))
    assert_predicate day, :persisted?
    assert_predicate day, :completed?
    assert_toast I18n.t("tasks.notices.completed")

    delete event_day_completion_path(event, "2026-03-23"), as: :turbo_stream
    assert_response :success
    assert_predicate day.reload, :pending?
    assert_toast I18n.t("tasks.notices.uncompleted")
  end

  test "taking away a completion a day never had changes nothing" do
    event = events(:water_the_plants)

    assert_no_difference -> { event.occurrences.count } do
      delete event_day_completion_path(event, "2026-03-23"), as: :turbo_stream
    end
    assert_response :success
  end

  test "money coming in is marked received, not paid" do
    event = series!("Transaction", profile: @alice, starts_on: Date.new(2026, 3, 23), title: "Salary", kind: :income)

    post event_day_completion_path(event, "2026-03-23"), as: :turbo_stream
    assert_toast I18n.t("transactions.notices.received")

    delete event_day_completion_path(event, "2026-03-23"), as: :turbo_stream
    assert_toast I18n.t("transactions.notices.unreceived")
  end

  test "a day of someone else's series is not found" do
    sign_in profiles(:outsider)
    get root_path

    post event_day_completion_path(events(:water_the_plants), "2026-03-23"), as: :turbo_stream
    assert_response :not_found
  end
end
