# frozen_string_literal: true

require "test_helper"

# A day's status, set from the "more" menu on its card.
class DayStatusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @event = events(:water_the_plants) # Mondays from 2026-03-02
    sign_in @alice
  end

  test "skipping a day nothing was stored about stores it skipped, and the series' other days stay as they were" do
    patch event_day_status_path(@event, "2026-03-23"), params: { status: "skipped" }, as: :turbo_stream

    assert_response :success
    assert_toast I18n.t("calendar.occurrences.notices.status.skipped")
    assert_predicate @event.occurrences.find_by!(date: Date.new(2026, 3, 23)), :skipped?
    assert_predicate @event.occurrence_on(Date.new(2026, 3, 30)), :pending?
  end

  test "a cancelled day is set back to pending" do
    patch event_day_status_path(@event, "2026-03-23"), params: { status: "cancelled" }, as: :turbo_stream
    day = @event.occurrences.find_by!(date: Date.new(2026, 3, 23))
    assert_predicate day, :cancelled?

    patch event_day_status_path(@event, "2026-03-23"), params: { status: "pending" }, as: :turbo_stream

    assert_toast I18n.t("calendar.occurrences.notices.status.pending")
    assert_predicate day.reload, :pending?
  end

  test "a dose is named by its time, and only that dose is skipped" do
    event = timed_medication!(profile: @alice, starts_on: Date.new(2026, 10, 1), times: %w[08:00 20:00]).event

    patch event_day_status_path(event, "2026-10-03", time: "20:00"), params: { status: "skipped" }, as: :turbo_stream

    doses = event.occurrences_between(Date.new(2026, 10, 3), Date.new(2026, 10, 3)).index_by(&:time_string)
    assert_equal({ "08:00" => "pending", "20:00" => "skipped" }, doses.transform_values(&:status))
  end

  test "a status the menu doesn't offer is refused, and the day is left as it was" do
    assert_no_difference -> { @event.occurrences.count } do
      patch event_day_status_path(@event, "2026-03-23"), params: { status: "completed" }, as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_toast I18n.t("refusals.unknown_choice")
  end

  test "a linked housemate's skip waits for the owner, who approves it through the same save" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", write: :ask)
    sign_in @bob

    assert_difference "LinkApproval.count", 1 do
      patch event_day_status_path(@event, "2026-03-23"), params: { status: "skipped" }, as: :turbo_stream
    end
    assert_toast I18n.t("links.notices.asked", name: @alice.display_name)
    assert_predicate @event.occurrence_on(Date.new(2026, 3, 23)), :pending?

    approval = LinkApproval.last
    assert_equal [ "update", { "status" => "skipped" } ], [ approval.action_kind, approval.payload["task"].slice("status") ]

    sign_in @alice
    post link_approval_consent_path(approval), as: :turbo_stream

    assert_predicate @event.occurrences.find_by!(date: Date.new(2026, 3, 23)), :skipped?
  end

  test "a linked housemate whose grant doesn't let them change the owner's days is refused" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", write: :off)
    sign_in @bob

    patch event_day_status_path(@event, "2026-03-23"), params: { status: "skipped" }, as: :turbo_stream

    assert_response :forbidden
    assert_predicate @event.occurrence_on(Date.new(2026, 3, 23)), :pending?
  end

  test "a day of someone else's series is not found" do
    sign_in profiles(:outsider)

    patch event_day_status_path(@event, "2026-03-23"), params: { status: "skipped" }, as: :turbo_stream

    assert_response :not_found
  end
end
