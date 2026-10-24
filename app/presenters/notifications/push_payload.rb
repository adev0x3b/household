# frozen_string_literal: true

module Notifications
  # What a push carries: a Declarative Web Push message (the Push API's
  # `web_push: 8030` shape), which Safari shows by itself and our service
  # worker reads everywhere else. In the recipient's language, with its two
  # addresses on the site the device subscribed on: `navigate`, where a tap
  # goes, and `read`, which the service worker posts first. Where Safari
  # shows the message without the worker, the tap still goes there and the
  # notification stays unread under the bell.
  class PushPayload
    def initialize(notification, subscription, navigate:, read:)
      @notification = notification
      @subscription = subscription
      @navigate = navigate
      @read = read
    end

    def as_json(*)
      @notification.profile.as_viewer do
        wording = Notifications::Wording.new(@notification)
        {
          web_push: 8030,
          notification: {
            title: wording.title,
            body: wording.detail.to_s,
            lang: I18n.locale.to_s,
            dir: "ltr",
            tag: "notification-#{@notification.id}",
            navigate: @subscription.url_for(@navigate),
            silent: false,
            data: { read: @subscription.url_for(@read) }
          },
          app_badge: @notification.profile.notifications.unread.count
        }
      end
    end

    def to_json(*) = as_json.to_json
  end
end
