# frozen_string_literal: true

require "test_helper"

class LinkGrantTest < ActiveSupport::TestCase
  test "every kind of series can be granted" do
    assert_equal Event::TYPES, LinkGrant::TYPES
  end

  test "a grant names its kind of series" do
    link!(profiles(:alice), profiles(:bob))
    grants = LinkGrant.where(grantor: profiles(:alice), grantee: profiles(:bob))

    assert_equal Event.types.to_set, grants.to_set(&:kind)
  end

  test "without read nothing else is allowed" do
    link!(profiles(:alice), profiles(:bob))
    grant = LinkGrant.find_by!(grantor: profiles(:alice), grantee: profiles(:bob), event_type: "Meal")

    grant.update!(read_level: :off, write_level: :on)
    assert_equal(%i[off off off off], LinkGrant::ACTIONS.map { grant.level(_1) })
  end

  test "a change is read at once, in its own transaction too, and forgotten if it rolls back" do
    alice, bob = profiles(:alice), profiles(:bob)
    link!(alice, bob)
    write = -> { Links::Permissions.for(bob).level(alice.id, "Task", :write) }

    LinkGrant.transaction(requires_new: true) do
      assert_equal :ask, write.call
      grant(alice, bob, "Task", write: :on)
      assert_equal :on, write.call, "the demo's seeder changes grants and acts on them in one transaction"
      raise ActiveRecord::Rollback
    end
    assert_equal :ask, write.call

    Link.transaction(requires_new: true) do
      Link.between(alice, bob).destroy!
      assert_equal :off, write.call
      raise ActiveRecord::Rollback
    end
    assert_equal :ask, write.call
  end

  test "read has no ask" do
    link!(profiles(:alice), profiles(:bob))
    grant = LinkGrant.find_by!(grantor: profiles(:alice), grantee: profiles(:bob), event_type: "Meal")

    grant.read_level = :ask
    assert_not grant.valid?
  end

  test "a level outside an action's scale is refused, never raised" do
    link!(profiles(:alice), profiles(:bob))
    grant = LinkGrant.find_by!(grantor: profiles(:alice), grantee: profiles(:bob), event_type: "Meal")

    %w[write create delete].each do |action|
      grant.assign_attributes("#{action}_level" => "sometimes")
      assert_not grant.valid?
      assert_includes grant.errors.attribute_names, :"#{action}_level"
      grant.restore_attributes
    end
  end
end
