# frozen_string_literal: true

require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "rejects a connection without a signed-in profile" do
    assert_reject_connection { connect env: { "warden" => FakeWarden.new(nil) } }
  end

  test "identifies the signed-in profile" do
    connect env: { "warden" => FakeWarden.new(profiles(:alice)) }
    assert_equal profiles(:alice), connection.current_profile
  end

  FakeWarden = Struct.new(:profile) do
    def user(_scope) = profile
  end
end
