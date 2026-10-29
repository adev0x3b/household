# frozen_string_literal: true

require "test_helper"

# Changing one's password: the one in use first, then a new one held to
# Profile's rules, which the person's record never holds before they pass.
class Accounts::PasswordChangeTest < ActiveSupport::TestCase
  PASSWORD = "alice's long password"

  setup do
    @alice = profiles(:alice).tap { _1.update!(password: PASSWORD, password_confirmation: PASSWORD) }
  end

  def change(current_password: PASSWORD, password: "a brand new password", password_confirmation: password)
    Accounts::PasswordChange.new(@alice, current_password:, password:, password_confirmation:)
  end

  test "with the password in use, the new one takes its place" do
    assert change.save

    assert @alice.reload.valid_password?("a brand new password")
  end

  test "a wrong password in use changes nothing and counts as a wrong sign-in" do
    form = change(current_password: "a guess")

    assert_not form.save
    assert form.errors.of_kind?(:current_password, :invalid)
    assert @alice.reload.valid_password?(PASSWORD)
    assert_equal 1, @alice.failed_attempts
  end

  test "a new password Devise refuses is said on its own field, before the one in use is tried" do
    short = change(current_password: "a guess", password: "short")
    assert_not short.save
    assert short.errors.of_kind?(:password, :too_short)

    unlike = change(password_confirmation: "another one entirely")
    assert_not unlike.save
    assert unlike.errors.of_kind?(:password_confirmation, :confirmation)

    blank = change(password: "")
    assert_not blank.save
    assert blank.errors.of_kind?(:password, :blank)

    assert_equal 0, @alice.reload.failed_attempts
    assert_not @alice.changed?, "the person's record holds no password refused"
    assert @alice.valid_password?(PASSWORD)
  end
end
