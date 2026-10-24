# frozen_string_literal: true

require "test_helper"

class CalendarChannelTest < ActionCable::Channel::TestCase
  setup { stub_connection current_profile: profiles(:alice) }

  test "subscribes to the profile's own month room, which every process then knows is open until it closes" do
    subscribe room: "profile_#{profiles(:alice).id}:2026-09"
    assert_predicate subscription, :confirmed?
    assert_has_stream "profile_#{profiles(:alice).id}:2026-09"
    assert_equal [ "2026-09" ], CalendarWatch.months_for(profiles(:alice).id)

    unsubscribe
    assert_empty CalendarWatch.months_for(profiles(:alice).id)
  end

  test "rejects another profile's room, and nothing is watched" do
    subscribe room: "profile_#{profiles(:bob).id}:2026-09"
    assert_predicate subscription, :rejected?
    assert_empty CalendarWatch.all
  end

  test "rejects a malformed room" do
    subscribe room: "profile_#{profiles(:alice).id}:2026-09x"
    assert_predicate subscription, :rejected?
  end
end
