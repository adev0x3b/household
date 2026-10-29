# frozen_string_literal: true

require "test_helper"

# How much mail about their accounts a household's people may still have:
# every person's together, against half of each of the installation's budgets.
class Emails::AccountMailAllowanceTest < ActiveSupport::TestCase
  def mailed(profile, at:, kind: :password_changed, status: :sent)
    OutgoingEmail.create!(profile:, kind:, status:, message_id: SecureRandom.uuid, claimed_at: at, not_before: at, expires_at: at)
  end

  def allowance(now = Time.current) = Emails::AccountMailAllowance.new(households(:example), now)

  test "counts the household's account mail in the rolling hour against half the hourly budget, rounded up" do
    freeze_time
    with_env("MAILS_PER_HOUR" => "5") do
      mailed(profiles(:alice), at: 10.minutes.ago)
      mailed(profiles(:bob), at: 20.minutes.ago, kind: :email_confirmation, status: :failed)
      mailed(profiles(:carol), at: 2.hours.ago)
      mailed(profiles(:outsider), at: 10.minutes.ago)
      mailed(profiles(:carol), at: 10.minutes.ago, kind: :reminder)
      mailed(profiles(:carol), at: 10.minutes.ago, kind: :test_mail)
      assert_predicate allowance, :any_left?, "two of three, a refused mail counted; not another household's, a reminder or a test"

      mailed(profiles(:carol), at: 5.minutes.ago, kind: :password_link)
      assert_not allowance.any_left?
      assert_predicate allowance(51.minutes.from_now), :any_left?
    end
  end

  test "and in the rolling day against half the daily budget" do
    freeze_time
    with_env("MAILS_PER_DAY" => "6") do
      3.times { |hours| mailed(profiles(:alice), at: (hours + 2).hours.ago) }
      assert_not allowance.any_left?
      assert_predicate allowance(21.hours.from_now), :any_left?
    end
  end
end
