# frozen_string_literal: true

require "test_helper"

# A relay that refused this copy's settings pauses the mail for a quarter
# of an hour, in the cache every process reads, with what to fix.
class Emails::RelayPauseTest < ActiveSupport::TestCase
  setup { Rails.cache = ActiveSupport::Cache::MemoryStore.new }
  teardown { Rails.cache = ActiveSupport::Cache::NullStore.new }

  test "keeps what to fix and the relay's reply, with no address in it, for a quarter of an hour" do
    Emails::RelayPause.start(Emails::Relay::Misconfigured.new(:sender, reply: "553 5.7.1 <household@household.example>:\r\nSender address rejected"))

    pause = Emails::RelayPause.current
    assert_equal :sender, pause.problem
    assert_equal "553 5.7.1 <[address]>: Sender address rejected", pause.reply
    assert_in_delta 15.minutes.from_now, pause.ends_at, 1.second

    travel 16.minutes
    assert_nil Emails::RelayPause.current
  end

  test "ends when cleared, as a test mail does" do
    Emails::RelayPause.start(Emails::Relay::Misconfigured.new(:password))
    assert_nil Emails::RelayPause.current.reply

    Emails::RelayPause.clear
    assert_nil Emails::RelayPause.current
  end
end
