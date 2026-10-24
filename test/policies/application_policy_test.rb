# frozen_string_literal: true

require "test_helper"

# What every policy starts from: every action refused, and the questions
# every policy shares: whose the record is, and whether it is
# shared with the user.
class ApplicationPolicyTest < ActiveSupport::TestCase
  class Probe < ApplicationPolicy
    def owner_asked? = owner?
    def shared_asked? = shared?
  end

  class ThroughList < Probe
    private

    def owning_record = record.grocery_list
  end

  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @list = GroceryList.create!(profile: @alice, name: "Week")
  end

  test "every action is refused until a policy allows it" do
    policy = ApplicationPolicy.new(@alice, @list)

    %i[index? show? create? new? update? edit? destroy?].each do |action|
      assert_not policy.public_send(action), "#{action} should be refused"
    end
  end

  test "the form actions follow the actions that save them" do
    creator = Class.new(ApplicationPolicy) { def create? = true }
    updater = Class.new(ApplicationPolicy) { def update? = true }

    assert_predicate creator.new(@alice, @list), :new?
    assert_predicate updater.new(@alice, @list), :edit?
  end

  test "a list's scope must be said by the policy that is asked for one" do
    assert_raises(NotImplementedError) { ApplicationPolicy::Scope.new(@alice, GroceryList).resolve }
  end

  test "the owner is the record's profile, and a share is read off the thing's shares" do
    assert_predicate Probe.new(@alice, @list), :owner_asked?
    assert_not Probe.new(@bob, @list).owner_asked?
    assert_not Probe.new(@bob, @list).shared_asked?

    Shares::Create.call(@list, with: @bob, by: @alice)

    assert_predicate Probe.new(@bob, @list.reload), :shared_asked?
  end

  test "a record that belongs to something else answers through it" do
    item = @list.grocery_list_items.build
    Shares::Create.call(@list, with: @bob, by: @alice)

    assert_predicate ThroughList.new(@alice, item), :owner_asked?
    assert_predicate ThroughList.new(@bob, item), :shared_asked?
  end

  test "a record whose owning record is missing is no one's" do
    assert_not ThroughList.new(@alice, GroceryListItem.new).owner_asked?
  end

  test "what can't be shared is never shared" do
    assert_not Probe.new(@bob, Notification.new(profile: @alice)).shared_asked?
  end
end
