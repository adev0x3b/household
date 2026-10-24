# frozen_string_literal: true

require "test_helper"

# A time is shown on the clock of whoever the page is for, even when the
# record was first read in another zone (Active Record keeps that one).
class Components::TimeDisplayTest < ActiveSupport::TestCase
  class Shown < Components::Base
    def initialize(at:) = @at = at
    def view_template = plain(l(@at, format: "%H:%M %Z"))
  end

  test "l() puts a time on the zone in scope" do
    message = send_message(Conversation.direct_between(profiles(:alice), profiles(:bob)), profiles(:bob), "hi")
    message.update_columns(created_at: Time.utc(2026, 10, 14, 22, 30))
    read_first = Time.use_zone("UTC") { message.reload.created_at }

    shown = Time.use_zone("Europe/Rome") { Shown.new(at: read_first).call }

    assert_equal "00:30 CEST", shown
  end
end
