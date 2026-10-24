# frozen_string_literal: true

require "test_helper"

# Whose calendar a new item can go on is read per kind of series: a partner
# who lets one add tasks has said nothing about medications.
class Links::PermissionsTest < ActiveSupport::TestCase
  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
    link!(@alice, @bob)
    LinkGrant.where(grantor: @alice, grantee: @bob).update_all(create_level: LinkGrant::LEVELS[:off])
  end

  test "a new item goes on a partner's calendar only for the kinds they let one add, or ask to" do
    grant(@alice, @bob, "Task", create: :on)
    grant(@alice, @bob, "Meal", create: :ask)
    permissions = Links::Permissions.for(@bob)

    assert_equal [ @bob, @alice ], permissions.creatable_owners("Task")
    assert_equal [ @bob, @alice ], permissions.creatable_owners("Meal")
    assert_equal [ @bob ], permissions.creatable_owners("Medication"), "Alice lets Bob add tasks and meals, not medications"
  end

  test "a kind one may change but not add to offers only one's own calendar" do
    grant(@alice, @bob, "Task", write: :on)

    assert_equal [ @bob ], Links::Permissions.for(@bob).creatable_owners("Task")
  end
end
