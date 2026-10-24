# frozen_string_literal: true

require "test_helper"

# Admin::Sudo: the window the admin's password opens in their session,
# what a wrong password costs, and who is asked at all.
class Admin::SudoTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice).tap { _1.update!(password: "a-long-enough-password", password_confirmation: "a-long-enough-password") }
    @session = {}
    @sudo = Admin::Sudo.new(@session, @alice)
  end

  test "the right password opens the window for a while" do
    assert_not @sudo.active?
    assert @sudo.verify("a-long-enough-password")
    assert_predicate @sudo, :active?
    travel(Admin::Sudo::FOR + 1.minute) { assert_not @sudo.active? }
  end

  test "a wrong or missing password opens nothing and counts as a wrong sign-in" do
    assert_not @sudo.verify("")
    assert_not @sudo.verify("not it")
    assert_not @sudo.active?
    assert_equal 1, @alice.reload.failed_attempts
    assert @sudo.verify("a-long-enough-password")
    assert_equal 0, @alice.reload.failed_attempts
  end

  test "only the admin is asked, and only until the window opens" do
    assert_not @sudo.required?, "a member's own powers need no second password"
    assert @sudo.passed?(nil)

    @alice.update!(role: :admin)
    assert_predicate @sudo, :required?
    assert_not @sudo.passed?(nil)
    assert_not @sudo.passed?("not it")
    assert @sudo.passed?("a-long-enough-password")
    assert_not @sudo.required?
    assert @sudo.passed?(nil)
  end
end
