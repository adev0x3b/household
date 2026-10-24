# frozen_string_literal: true

require "test_helper"

class LinkTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
  end

  test "two housemates link once, never with themselves or across households" do
    assert_predicate Link.new(requester: @alice, addressee: @bob), :valid?
    assert_predicate Link.new(requester: @alice, addressee: @alice), :invalid?

    outsider = Link.new(requester: @alice, addressee: profiles(:outsider))
    assert_not outsider.valid?
    assert outsider.errors.of_kind?(:addressee, :outside_household)

    Link.create!(requester: @alice, addressee: @bob)
    assert_not Link.new(requester: @bob, addressee: @alice).valid?, "one link per pair, whoever asks"
    assert_equal Link.between(@bob, @alice), Link.between(@alice, @bob)
  end

  test "someone still invited can't be linked" do
    @bob.update_columns(invitation_token: "pending")
    link = Link.new(requester: @alice, addressee: @bob)

    assert_not link.valid?
    assert link.errors.of_kind?(:addressee, :not_housemate)
  end

  test "an accepted link has every kind's grants both ways, read on and the rest asked" do
    link = link!(@alice, @bob)

    assert_equal LinkGrant::TYPES.size * 2, link.link_grants.count
    grant = LinkGrant.find_by!(grantor: @alice, grantee: @bob, event_type: "Task")
    assert_equal(%i[on ask ask ask], LinkGrant::ACTIONS.map { grant.level(_1) })
    assert_equal LinkGrant::TYPES, link.grants_from(@alice).map(&:event_type)

    link.ensure_grants!
    assert_equal LinkGrant::TYPES.size * 2, link.link_grants.count, "ensuring again adds nothing"
  end

  test "a kind with no row yet reads as off, and is not saved by reading it" do
    link = link!(@alice, @bob)
    LinkGrant.where(link: link, grantor: @alice, event_type: "Meal").delete_all
    link.link_grants.reset

    grants = link.grants_from(@alice)
    assert_equal LinkGrant::TYPES, grants.map(&:event_type)
    meal = grants.find { _1.event_type == "Meal" }
    assert_predicate meal, :new_record?
    assert_equal(%i[off off off off], LinkGrant::ACTIONS.map { meal.level(_1) })
    assert_equal [ @alice.id, @bob.id, link.id ], [ meal.grantor_id, meal.grantee_id, meal.link_id ]
    assert_predicate link.grant_from(@alice, "Meal"), :new_record?
    assert_predicate link.grant_from(@alice, "Task"), :persisted?

    link.save!
    assert_not LinkGrant.exists?(link: link, grantor: @alice, event_type: "Meal")
  end

  test "a pending link has no grants" do
    link = Link.create!(requester: @alice, addressee: @bob)
    link.ensure_grants!

    assert_empty link.link_grants
    assert_empty @alice.link_partners
  end

  test "partners are the accepted links either way" do
    link!(@alice, @bob)
    Link.create!(requester: profiles(:carol), addressee: @alice)

    assert_equal [ @bob ], @alice.link_partners.to_a
    assert_equal [ @alice ], @bob.link_partners.to_a
  end
end
