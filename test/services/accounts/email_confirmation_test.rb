# frozen_string_literal: true

require "test_helper"

# Confirming an address from its link's page takes the password in use as
# well as the link, so an address someone else typed, an inviter's, becomes
# where links to set a password go only by the person's own hand.
class Accounts::EmailConfirmationTest < ActiveSupport::TestCase
  PASSWORD = "alice's long password"

  setup do
    @alice = profiles(:alice)
    @alice.update!(password: PASSWORD, password_confirmation: PASSWORD)
    @token = @alice.email_confirmation_token!
  end

  test "the link and the password confirm the address" do
    confirmation = Accounts::EmailConfirmation.new(@alice, token: @token, current_password: PASSWORD)

    assert_equal "alice@example.com", confirmation.address
    assert confirmation.save
    assert_predicate @alice.reload, :email_confirmed?
  end

  test "a session alone confirms nothing: no password, or a wrong one, is refused on its field and brings the lock nearer" do
    [ "", "not the password" ].each do |password|
      confirmation = Accounts::EmailConfirmation.new(@alice, token: @token, current_password: password)

      assert_not confirmation.save
      assert_nil confirmation.problem
      assert_predicate confirmation.errors[:current_password], :any?
    end

    @alice.reload
    assert_equal 1, @alice.failed_attempts
    assert_not @alice.email_confirmed?
  end

  test "a link that can't confirm says why, and asks for no password" do
    bob = profiles(:bob)
    confirmation = Accounts::EmailConfirmation.new(bob, token: @token, current_password: "a guess")

    assert_equal :not_yours, confirmation.problem
    assert_not confirmation.save
    assert_equal 0, bob.reload.failed_attempts
  end
end
