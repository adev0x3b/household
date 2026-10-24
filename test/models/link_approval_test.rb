# frozen_string_literal: true

require "test_helper"

# "Changed since it was asked": the owner is told when the day a request is
# about changed after it was made — its own row or its series', down to a
# kind's own fields and the times of the day.
class LinkApprovalTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    link!(@alice, @bob)
    @series = events(:water_the_plants) # Alice's "Water the plants", Mondays from 2026-03-02
    @day = @series.occurrence_on(Date.new(2026, 3, 9)).tap { _1.update!(notes: "With the rain water") }
    @approval = Links::Approvals::Hold.call(requester: @bob, record: @day, kind: :complete)
  end

  def later(&) = travel(1.minute, &)

  test "nothing changed, nothing to say" do
    assert_not @approval.changed_since?
  end

  test "the day itself changed" do
    later { @day.update!(notes: "With tap water") }
    assert_predicate @approval.reload, :changed_since?
  end

  test "the whole series changed, though the day has a row of its own" do
    later { @series.update!(title: "Water every plant") }
    assert_predicate @approval.reload, :changed_since?
  end

  test "only a kind's own field changed: on the series, or on the day alone" do
    later { @series.details.update!(priority: :urgent) }
    assert_predicate @approval.reload, :changed_since?, "the series' row"

    approval = Links::Approvals::Hold.call(requester: @bob, record: @day, kind: :uncomplete)
    travel(2.minutes) { Task::Details.create!(event: @series, occurrence: @day, priority: :low) }
    assert_predicate approval.reload, :changed_since?, "the day's own row"
  end

  test "the times of the day changed" do
    later do
      @series.assign_slots([ "08:00" ])
      @series.save!
    end
    assert_predicate @approval.reload, :changed_since?
  end

  test "another day changing alone is not this one changing" do
    later { @series.occurrence_on(Date.new(2026, 3, 16)).update!(notes: "Skip the cactus") }
    assert_not @approval.reload.changed_since?
  end
end
