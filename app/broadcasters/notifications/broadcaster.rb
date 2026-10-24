# frozen_string_literal: true

module Notifications
  # Pushes a profile's notifications to its open pages, over the profile's
  # signed stream (`turbo_stream_from profile, :notifications` in the
  # layout), in the recipient's language, not the sender's.
  #
  # What it targets, each named by what draws it:
  #   the unread count on the bell        Views::Notifications::Badge::SELECTOR
  #   the rows, once the dropdown opened  Views::Notifications::List::LIST_ID
  #   one row                             Views::Notifications::Item.dom_id
  #   the toasts                          Components::Toast::CONTAINER_ID
  class Broadcaster < ApplicationBroadcaster
    # A new notification: the count, its row on top of the list, a toast.
    # (A refreshed one too: prepending a row whose id is already in the
    # list moves it to the top.)
    def self.delivered(notification)
      quietly do
        profile = notification.profile
        as(profile) do
          wording = Notifications::Wording.new(notification)
          badge(profile)
          stream_to([ profile, :notifications ], :prepend, Views::Notifications::Item.new(notification: notification), target: Views::Notifications::List::LIST_ID)
          stream_to([ profile, :notifications ], :append, Components::Toast.new(kind: wording.toast_kind, body: wording.title, detail: wording.detail),
                    target: Components::Toast::CONTAINER_ID)
        end
      end
    end

    # Its row redrawn where it is (its question answered, say): no toast.
    def self.refreshed(notification)
      quietly do
        as(notification.profile) do
          stream_to([ notification.profile, :notifications ], :replace, Views::Notifications::Item.new(notification: notification),
                    target: Views::Notifications::Item.dom_id(notification))
        end
      end
    end

    # The unread count, after reading on one page, for the others.
    def self.badge(profile)
      quietly do
        stream_to([ profile, :notifications ], :replace, Views::Notifications::Badge.new(count: profile.notifications.unread.count),
                  targets: Views::Notifications::Badge::SELECTOR)
      end
    end
  end
end
