# frozen_string_literal: true

require "test_helper"

# Every kind of mail, as the outbox and the drain ask of it.
class Emails::KindsTest < ActiveSupport::TestCase
  test "every kind is one the outbox holds, and answers what the drain asks of a kind" do
    Emails::Kinds.all.each do |kind|
      assert_operator kind, :<, Emails::Kind
      assert_includes OutgoingEmail.kinds.keys, kind.key.to_s, kind.name
      assert_kind_of ActiveSupport::Duration, kind.waits_at_most, kind.name
      [ kind.account?, kind.sends_at_once?, kind.room_in?(households(:example), Time.current) ].each do |answer|
        assert_includes [ true, false ], answer, kind.name
      end
      assert kind.public_method_defined?(:message), kind.name
    end
  end

  test "the outbox holds no kind of mail without its class" do
    assert_equal OutgoingEmail.kinds.keys.sort, Emails::Kinds.all.map { _1.key.to_s }.sort
  end

  test "a kind is found by its key; a key no kind has is refused to whoever queues, and nothing to a drain" do
    assert_equal Emails::Kinds::TestMail, Emails::Kinds.for("test_mail")
    assert_raises(ArgumentError) { Emails::Kinds.for(:newsletter) }
    assert_nil Emails::Kinds.find(:newsletter)
    assert_nil Emails::Kinds.find(nil)
  end
end
