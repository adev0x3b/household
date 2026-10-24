# frozen_string_literal: true

require "test_helper"

# What a card or a form may let the viewer do with a day, as the day's
# policy answers: the owner everything, a linked housemate what the grant
# says, sometimes only once the owner agrees, and nobody signed in nothing.
class Occurrences::AccessTest < ActiveSupport::TestCase
  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
    @day = task!(profile: @alice, date: Date.new(2027, 3, 2), title: "Bins")
  end

  test "the owner may do everything, and is never asked" do
    access = Occurrences::Access.new(@day, @alice)

    assert_predicate access, :owner?
    assert access.allows?(:change_status?)
    assert access.allows?(:destroy?)
    assert_not access.asks?(:destroy?)
  end

  test "a linked housemate may what the grant lets, and asks where it says so" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", write: :on, delete: :ask)
    access = Occurrences::Access.new(@day, @bob)

    assert_not_predicate access, :owner?
    assert access.allows?(:change_status?)
    assert access.allows?(:destroy?), "deleting is allowed, pending the owner's OK"
    assert access.asks?(:destroy?)
    assert_not access.asks?(:change_status?)
  end

  test "a housemate without a link may only look on, and nobody signed in may do nothing" do
    stranger = Occurrences::Access.new(@day, @bob)
    nobody = Occurrences::Access.new(@day, nil)

    assert_not stranger.allows?(:show?)
    assert_not stranger.allows?(:change_status?)
    assert_not_predicate nobody, :viewer?
    assert_not_predicate nobody, :owner?
    assert_not nobody.allows?(:show?)
    assert_not nobody.asks?(:show?)
  end

  test "a new series may go on the viewer's calendar, and on a linked housemate's who lets them add there" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", create: :on)
    new_task = Task.new(profile: @bob).occurrence_on(Date.current)

    assert_equal [ @bob, @alice ], Occurrences::Access.new(new_task, @bob).creatable_owners
    carol = profiles(:carol)
    assert_equal [ carol ], Occurrences::Access.new(Task.new(profile: carol).occurrence_on(Date.current), carol).creatable_owners, "no link, one's own"
    assert_empty Occurrences::Access.new(@day, @alice).creatable_owners, "a series that exists is already on a calendar"
    assert_empty Occurrences::Access.new(new_task, nil).creatable_owners
  end
end
