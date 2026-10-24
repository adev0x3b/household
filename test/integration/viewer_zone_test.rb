# frozen_string_literal: true

require "test_helper"

# "Today" is the viewer's: at half past midnight in Rome it is
# already tomorrow there, while the server's clock (UTC) still says today.
class ViewerZoneTest < ActionDispatch::IntegrationTest
  ROME_PAST_MIDNIGHT = Time.utc(2026, 10, 14, 22, 30) # 00:30 on the 15th in Rome (CEST)

  setup { @alice = profiles(:alice).tap { _1.update!(time_zone: "Europe/Rome") } }
  teardown { travel_back }

  test "the calendar's today and the home's are the viewer's day, not the server's" do
    sign_in @alice
    travel_to ROME_PAST_MIDNIGHT

    get calendar_path
    assert_select "#day_2026-10-15.day-card--today"
    assert_select "#day_2026-10-14.day-card--today", 0

    get root_path
    assert_select "#day_2026-10-15"
  end

  test "someone whose browser hasn't said a zone yet gets the app's" do
    sign_in profiles(:bob)
    travel_to ROME_PAST_MIDNIGHT

    get calendar_path
    assert_select "#day_2026-10-14.day-card--today"
  end

  test "a month that isn't one opens today's, instead of failing" do
    sign_in @alice
    travel_to ROME_PAST_MIDNIGHT

    [ { month: 13, year: 2026 }, { month: 0, year: 2026 }, { month: 2, year: 99_999 }, { month: "x" } ].each do |params|
      get calendar_path(params)
      assert_response :success, params.inspect
      assert_select "#day_2026-10-15.day-card--today"
    end

    get calendar_path(month: 3)
    assert_select "#day_2026-03-01", 1, "a month without a year is this year's"
  end
end
