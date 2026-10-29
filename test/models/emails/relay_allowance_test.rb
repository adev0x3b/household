# frozen_string_literal: true

require "test_helper"

# What the installation may still mail in the rolling hour and day, every
# household together, and what it keeps for account mail.
class Emails::RelayAllowanceTest < ActiveSupport::TestCase
  def taken(count, at:, status: :sent, message_id: nil)
    count.times do
      OutgoingEmail.create!(profile: profiles(:alice), kind: :test_mail, status: status, not_before: at, expires_at: at + 15.minutes,
                            claimed_at: at, message_id: message_id || "#{SecureRandom.uuid}@household.example")
    end
  end

  test "counts the messages taken in the rolling hour and day, on their way, gone or refused, rows sent together as one" do
    taken(1, at: 30.minutes.ago)
    taken(1, at: 20.minutes.ago, status: :sending)
    taken(3, at: 2.hours.ago, message_id: "together@household.example")
    taken(1, at: 25.hours.ago)
    taken(2, at: 10.minutes.ago, status: :failed)

    allowance = Emails::RelayAllowance.new
    assert_equal 6 - 4, allowance.left_this_hour
    assert_equal 40 - 5, allowance.left_today
  end

  test "account mail may take the last of each hour; the rest, the admin's tests too, leaves it" do
    taken(4, at: 10.minutes.ago)
    assert Emails::RelayAllowance.new.allows?(Emails::Kinds::TestMail), "two left this hour"

    taken(1, at: 5.minutes.ago)
    assert_not Emails::RelayAllowance.new.allows?(Emails::Kinds::TestMail)
    assert Emails::RelayAllowance.new.allows?(Emails::Kinds::PasswordChanged)

    taken(1, at: 1.minute.ago)
    assert_not Emails::RelayAllowance.new.allows?(Emails::Kinds::PasswordChanged)
  end

  test "account mail may take the last five of each day; the rest leaves them" do
    with_env("MAILS_PER_DAY" => "10", "MAILS_PER_HOUR" => "100") do
      taken(5, at: 3.hours.ago)
      assert_not Emails::RelayAllowance.new.allows?(Emails::Kinds::TestMail)
      assert Emails::RelayAllowance.new.allows?(Emails::Kinds::PasswordChanged)

      taken(5, at: 2.hours.ago)
      assert_not Emails::RelayAllowance.new.allows?(Emails::Kinds::PasswordChanged)
    end
  end
end
