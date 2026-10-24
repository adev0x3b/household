# frozen_string_literal: true

require "test_helper"

# Asking to link: for oneself, and only a housemate. What the other answers
# is the policy matrix's.
class LinkPolicyTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
  end

  def ask(by, from:, to:) = LinkPolicy.new(by, Link.new(requester: from, addressee: to)).create?

  test "one asks for oneself, a housemate only" do
    assert ask(@alice, from: @alice, to: @bob)
    assert_not ask(@bob, from: @alice, to: @bob), "never on someone else's behalf"
    assert_not ask(@alice, from: @alice, to: profiles(:outsider)), "never outside the household"
  end
end
