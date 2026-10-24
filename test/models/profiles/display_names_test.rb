# frozen_string_literal: true

require "test_helper"

class Profiles::DisplayNamesTest < ActiveSupport::TestCase
  test "each person is their name, with the username only where another shown has the same name" do
    alice, bob = profiles(:alice), profiles(:bob)
    other_alice = Profile.new(first_name: alice.first_name, username: "alice.2")
    names = Profiles::DisplayNames.new([ alice, bob, other_alice ])

    assert_equal bob.first_name, names.of(bob)
    assert_equal "#{alice.first_name} (#{alice.username})", names.of(alice)
    assert_equal "#{alice.first_name} (alice.2)", names.of(other_alice)
  end

  test "a person named by their username alone is never told apart by it" do
    zed = Profile.new(username: "zed")
    twin = Profile.new(username: "zed")

    assert_equal "zed", Profiles::DisplayNames.new([ zed, twin ]).of(zed)
  end
end
