# frozen_string_literal: true

require "test_helper"

# A day of a series, addressed by its series and date: its form and save,
# whether anything was stored about it yet, and deleting it from a calendar
# card (one dose of it, the day, or the series).
class DaysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bob = profiles(:bob)
    sign_in @bob
    @event = timed_medication!(profile: @bob, starts_on: Date.new(2026, 10, 1), times: %w[CM 20:00]).event
  end

  test "a day nothing was stored about opens its form, and saving it stores that day" do
    sign_in profiles(:alice)
    event = events(:water_the_plants) # Mondays from 2026-03-02

    get edit_event_day_path(event, "2026-03-16"), as: :turbo_stream
    assert_response :success
    assert_select "form[action=?][method=post]", event_day_path(event, "2026-03-16") do
      assert_select "input[name=_method][value=patch]", 1, "a day nothing was stored about is still a change to its series"
    end
    assert_select "input[name='task[title]'][value='Water the plants']"
    assert_select "input[type=hidden][name='task[event_id]']", 0, "the day is the form's address, not a field of it"
    assert_select "input[type=hidden][name='task[date]']", 0

    assert_difference -> { event.occurrences.count }, 1 do
      patch event_day_path(event, "2026-03-16"), as: :turbo_stream, params: {
        task: { title: "Water the plants and the herbs", details_attributes: { priority: "medium" } },
        event: { frequency: "weekly", interval: 1, week_days: %w[monday] }
      }
    end
    assert_equal "Water the plants and the herbs", event.occurrence_on(Date.new(2026, 3, 16)).title
    assert_equal "Water the plants", event.reload.title
  end

  test "a day nothing was stored about offers its status, and skipping it from the form stores it skipped" do
    sign_in profiles(:alice)
    event = events(:water_the_plants)

    get edit_event_day_path(event, "2026-03-16"), as: :turbo_stream
    assert_select "select[name='task[status]']" do
      assert_select "option[selected][value=pending]"
      assert_select "option", Task.allowed_statuses.size
    end

    patch event_day_path(event, "2026-03-16"), as: :turbo_stream, params: { task: { title: "Water the plants", status: "skipped" } }

    assert_predicate event.occurrences.find_by!(date: Date.new(2026, 3, 16)), :skipped?
    assert_equal "pending", event.occurrence_on(Date.new(2026, 3, 23)).status, "the series' other days are as they were"
  end

  test "a series that ends reads back as ending on its last day, however the end was given" do
    sign_in profiles(:alice)
    event = events(:water_the_plants) # Mondays from 2026-03-02

    patch event_day_path(event, "2026-03-02"), as: :turbo_stream, params: {
      task: { title: event.title, apply_to: "series" },
      event: { frequency: "weekly", interval: 1, week_days: %w[monday], ends_by: "after_times", ends_after_times: "3" }
    }
    get edit_event_day_path(event, "2026-03-09"), as: :turbo_stream

    assert_select "select[name='event[ends_by]'] option[selected][value=on_date]"
    assert_select "input[type=date][name='event[ends]'][value='2026-03-16']"
    assert_select "input[name='event[ends_after_days]']:not([value])"
  end

  test "an end that can't be is said under the end's field, drawn again as it was typed" do
    sign_in profiles(:alice)
    event = events(:water_the_plants)

    patch event_day_path(event, "2026-03-16"), as: :turbo_stream, params: {
      task: { title: event.title, apply_to: "series" },
      event: { frequency: "weekly", interval: 1, week_days: %w[monday], ends_by: "on_date", ends: "2026-02-01" }
    }

    assert_response :unprocessable_content
    assert_select "#event_ends_error", text: /can't end before its first day/
    assert_select "#event_ends[aria-invalid=true]"
    assert_select "select[name='event[ends_by]'] option[selected][value=on_date]"
    assert_select "#event_ends[value='2026-02-01']"
    assert_nil Events::RecurrenceRule.describe(event.reload.rrule)[:ends]
  end

  test "a dose nothing was stored about offers whether it was taken, when, and why not" do
    get edit_event_day_path(@event, "2026-10-03", time: "20:00"), as: :turbo_stream

    assert_select "select[name='medication[status]']"
    assert_select "select[name='medication[skipped_reason]']"
    assert_select "input[name='medication[completed_at]']"
  end

  test "a dose is named by its time, and a day without one is the dose still to take" do
    get edit_event_day_path(@event, "2026-10-03", time: "20:00"), as: :turbo_stream
    assert_select "form[action=?]", event_day_path(@event, "2026-10-03", time: "20:00")
    assert_select ".modal__header", text: /October 3, 2026/

    @event.occurrence_on(Date.new(2026, 10, 3), time: "08:00").complete!
    get edit_event_day_path(@event, "2026-10-03"), as: :turbo_stream
    assert_select "form[action=?]", event_day_path(@event, "2026-10-03", time: "20:00")
  end

  test "deleting one dose of a day leaves the day's other doses and the other days" do
    get calendar_path(month: 10, year: 2026)
    assert_select "#day_2026-10-03 .item-menu__button[data-card-menu-delete-url-param=?]", event_day_path(@event, "2026-10-03", time: "20:00")

    delete event_day_path(@event, "2026-10-03", time: "20:00"), params: { scope: "occurrence" }, as: :turbo_stream

    assert_response :success
    @event.reload
    assert_equal([ [ "08:00", "CM" ] ], @event.occurrences_between(Date.new(2026, 10, 3), Date.new(2026, 10, 3)).map { [ _1.time_string, _1.anchor ] })
    assert_equal 2, @event.occurrences_between(Date.new(2026, 10, 4), Date.new(2026, 10, 4)).size
  end

  test "deleting the series" do
    delete event_day_path(@event, "2026-10-03", scope: "series"), as: :turbo_stream

    assert_response :success
    assert_not Event.exists?(@event.id)
  end

  test "a day the series doesn't have, or a bad date, is not found" do
    get calendar_path(month: 10, year: 2026) # a 404 first would drop the test sign-in before its session is saved

    delete event_day_path(@event, "2026-09-03"), as: :turbo_stream
    assert_response :not_found
    delete event_day_path(@event, "2026-10-03", time: "13:00"), as: :turbo_stream
    assert_response :not_found
    delete event_day_path(@event, "not-a-date"), as: :turbo_stream
    assert_response :not_found
    get edit_event_day_path(@event, "not-a-date"), as: :turbo_stream
    assert_response :not_found
    assert Event.exists?(@event.id)
  end

  test "someone else's series is not found" do
    sign_in profiles(:carol)
    get calendar_path(month: 10, year: 2026)

    delete event_day_path(@event, "2026-10-03", scope: "series"), as: :turbo_stream
    assert_response :not_found
    get edit_event_day_path(@event, "2026-10-03"), as: :turbo_stream
    assert_response :not_found
    assert Event.exists?(@event.id)
  end
end
