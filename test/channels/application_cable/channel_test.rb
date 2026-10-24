# frozen_string_literal: true

require "test_helper"
require "action_cable/channel/test_case" # its ConnectionStub

# Action Cable's channel test case turns periodic timers off, so these build
# a channel on a stub connection themselves and count the timers it starts.
class ApplicationCable::ChannelTest < ActiveSupport::TestCase
  class Ticking < ApplicationCable::Channel
    periodically :tick, every: 1.minute

    def tick; end
  end

  # Its page is left while it subscribes: the connection, closing on another
  # thread, unsubscribes it before its timers start.
  class LeftWhileSubscribing < Ticking
    def subscribed
      Thread.new { unsubscribe_from_channel }.join
    end
  end

  Timer = Struct.new(:running) do
    def shutdown = self.running = false
  end

  setup { @timers = [] }

  test "a channel's timers run from its subscribe to its unsubscribe" do
    channel = subscribe(Ticking)
    assert_equal [ true ], @timers.map(&:running)

    channel.unsubscribe_from_channel
    assert_equal [ false ], @timers.map(&:running)
  end

  test "a channel unsubscribed while it subscribes starts no timers" do
    channel = subscribe(LeftWhileSubscribing)

    assert_predicate channel, :unsubscribed?
    assert_empty @timers, "nothing would ever stop them"
  end

  private

  def subscribe(channel_class)
    timers = @timers # the swapped method runs as the event loop, not as this test
    start_timer = ->(_interval, &_tick) { Timer.new(true).tap { |timer| timers << timer } }
    swapping(ActionCable.server.event_loop, :timer, start_timer) do
      channel_class.new(ActionCable::Channel::ConnectionStub.new, channel_class.name).tap(&:subscribe_to_channel)
    end
  end
end
