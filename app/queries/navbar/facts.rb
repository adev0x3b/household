# frozen_string_literal: true

module Navbar
  # What the bar on every signed-in page says about its person: the
  # unread messages, what waits for an answer on Links, the unread
  # notifications, and the devices this browser could be among (push
  # subscriptions, by their endpoints' digests). Read once per request by
  # the controller and handed to Views::Layouts::Navbar, so that no part of
  # the bar runs a query of its own.
  class Facts
    attr_reader :unread_messages, :pending_links, :unread_notifications, :push_digests

    def self.for(profile) = new(profile)

    def initialize(profile)
      @unread_messages = Messages::Unread.count_for(profile)
      @pending_links = Links::Pending.count_for(profile)
      @unread_notifications = profile.notifications.unread.count
      @push_digests = profile.push_subscriptions.pluck(:endpoint).map { PushSubscription.digest(_1) }
    end
  end
end
