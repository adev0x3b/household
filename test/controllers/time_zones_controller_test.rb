# frozen_string_literal: true

require "test_helper"

class TimeZonesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
  end

  test "the browser's time zone is saved on the profile, and a made-up one isn't" do
    patch time_zone_path, params: { time_zone: "Europe/Rome" }, as: :json
    assert_response :no_content
    assert_equal ActiveSupport::TimeZone["Europe/Rome"], @alice.reload.zone

    patch time_zone_path, params: { time_zone: "Mars/Olympus" }, as: :json
    assert_equal "Europe/Rome", @alice.reload.time_zone
  end

  test "every page tells the browser which one is saved" do
    @alice.update!(time_zone: "Europe/Rome")

    get root_path

    assert_select "[data-controller~=time-zone][data-time-zone-current-value='Europe/Rome'][data-time-zone-url-value=?]", time_zone_path
  end
end
