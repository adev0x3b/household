# frozen_string_literal: true

require "test_helper"

# How many links to set a password may still be mailed: per person and for
# the installation, every request counted, whatever came of it.
class Emails::PasswordLinkAllowanceTest < ActiveSupport::TestCase
  def asked(profile, at:, status: :sent)
    OutgoingEmail.create!(profile:, kind: :password_link, status:, not_before: at, expires_at: at, created_at: at)
  end

  test "counts a person's requests of the rolling day, sent, dropped or failed, and no other kind of mail" do
    alice = profiles(:alice)
    asked(alice, at: 23.hours.ago, status: :failed)
    asked(alice, at: 12.hours.ago, status: :dropped)
    asked(alice, at: 25.hours.ago)
    OutgoingEmail.create!(profile: alice, kind: :email_confirmation, not_before: Time.current, expires_at: 1.hour.from_now)

    assert_predicate Emails::PasswordLinkAllowance.new(alice), :any_left?
    asked(alice, at: 3.hours.ago)
    assert_not Emails::PasswordLinkAllowance.new(alice).any_left?
  end

  test "the installation's hour and day, every household together" do
    asked(profiles(:outsider), at: 30.minutes.ago)
    asked(profiles(:bob), at: 10.minutes.ago)
    assert_not Emails::PasswordLinkAllowance.new(profiles(:alice)).any_left?
    assert_predicate Emails::PasswordLinkAllowance.new(profiles(:alice), 1.hour.from_now), :any_left?

    8.times { asked(profiles(:carol), at: 5.hours.ago) }
    assert_not Emails::PasswordLinkAllowance.new(profiles(:alice), 1.hour.from_now).any_left?
  end
end
