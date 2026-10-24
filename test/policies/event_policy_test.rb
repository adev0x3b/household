# frozen_string_literal: true

require "test_helper"

# A series as a whole is changed by whoever may change its days: its owner,
# whoever it is shared with, and a linked housemate whose grant doesn't turn
# writing off.
class EventPolicyTest < ActiveSupport::TestCase
  setup do
    @alice, @bob, @carol = profiles(:alice), profiles(:bob), profiles(:carol)
    @series = task!(profile: @alice, date: Date.new(2026, 10, 6)).event
    Links::Permissions.reset!
  end

  def update?(user) = EventPolicy.new(user, @series).update?

  test "its owner and whoever it is shared with change it; another housemate doesn't" do
    EventShare.create!(event: @series, profile: @bob)

    assert update?(@alice)
    assert update?(@bob)
    assert_not update?(@carol)
  end

  test "a linked housemate changes it unless the grant turns writing off" do
    link!(@alice, @bob)
    assert update?(@bob), "asked by default: the change is allowed and held"

    grant(@alice, @bob, "Task", write: :off)
    Links::Permissions.reset!
    assert_not update?(@bob)
  end
end
