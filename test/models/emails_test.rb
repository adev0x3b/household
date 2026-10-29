# frozen_string_literal: true

require "test_helper"

# Whether mail goes out, and whether it can reach a person.
class EmailsTest < ActiveSupport::TestCase
  setup { @alice = profiles(:alice) }

  test "reminders may come by email once mail goes out and the address is confirmed" do
    assert_equal :off, Emails.for_reminders(@alice), "no relay"
    with_relay { assert_equal :unconfirmed, Emails.for_reminders(@alice) }

    @alice.update!(email_confirmed_at: 1.day.ago)
    with_relay { assert_equal :available, Emails.for_reminders(@alice) }
    with_relay("OUTGOING_MAIL" => "off") { assert_equal :off, Emails.for_reminders(@alice) }
  end

  test "never to an open account, whose address is nobody's who uses it" do
    @alice.update!(email_confirmed_at: 1.day.ago)

    with_relay("OPEN_ACCOUNTS" => "alice") { assert_equal :off, Emails.for_reminders(@alice) }
  end

  test "not while the admin allows households no reminder mail, so no form offers it" do
    @alice.update!(email_confirmed_at: 1.day.ago)

    with_relay("REMINDER_MAILS_PER_DAY" => "0") { assert_equal :off, Emails.for_reminders(@alice) }
    with_relay("REMINDER_MAILS_PER_DAY" => "1") { assert_equal :available, Emails.for_reminders(@alice) }
  end

  test "what a relay answered is kept without the addresses in it" do
    assert_equal "550 <[address]>: no such user", Emails.without_addresses("550 <alice@example.com>: no such user")
  end
end
