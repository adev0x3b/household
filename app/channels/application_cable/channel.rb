# frozen_string_literal: true

module ApplicationCable
  # A page left while its channel is still subscribing closes the connection
  # on another of Action Cable's threads, which unsubscribes the channel
  # before its periodic timers have started. Action Cable starts them anyway,
  # once it has stopped the none there were, and they then run for as long as
  # the process does, for a page that is gone. So a channel already
  # unsubscribed starts none, and a lock keeps the unsubscribe from falling
  # between that check and the start.
  class Channel < ActionCable::Channel::Base
    def initialize(...)
      @periodic_timers_lock = Mutex.new
      super
    end

    private

    def start_periodic_timers
      @periodic_timers_lock.synchronize { super unless unsubscribed? }
    end

    def stop_periodic_timers
      @periodic_timers_lock.synchronize { super }
    end
  end
end
