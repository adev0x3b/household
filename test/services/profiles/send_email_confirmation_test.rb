# frozen_string_literal: true

require "test_helper"

# The link that confirms an address, mailed again: only where mail goes
# out, while there is something to confirm, a few times a day.
class Profiles::SendEmailConfirmationTest < ActiveSupport::TestCase
  setup { @alice = profiles(:alice) }

  test "queues the link for the address to confirm" do
    result = with_relay { Profiles::SendEmailConfirmation.call(@alice) }

    assert_predicate result, :success?
    assert_equal "email_confirmation", OutgoingEmail.sole.kind
  end

  test "nothing to send where no mail goes out, or nothing waits to be confirmed" do
    assert_equal :mail_off, Profiles::SendEmailConfirmation.call(@alice).error

    @alice.update!(email_confirmed_at: Time.current)
    assert_equal :nothing_to_confirm, with_relay { Profiles::SendEmailConfirmation.call(@alice) }.error

    @alice.update!(unconfirmed_email: "alice@new.example")
    assert_predicate with_relay { Profiles::SendEmailConfirmation.call(@alice) }, :success?
  end

  test "three links a day, counted with those an address change asked for" do
    with_relay do
      Emails::Enqueue.call(@alice, :email_confirmation)
      2.times { assert_predicate Profiles::SendEmailConfirmation.call(@alice), :success? }

      assert_equal :no_links_left, Profiles::SendEmailConfirmation.call(@alice).error
    end
    assert_equal 3, OutgoingEmail.count
  end
end
