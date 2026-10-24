# frozen_string_literal: true

module Notifications
  # Sends one notification to one device (Web Push, VAPID-signed, encrypted
  # for that browser). One job per device, so a slow or broken push service
  # only delays its own devices and a retry never repeats a push elsewhere.
  #
  # A device the push service no longer knows (404/410) is forgotten. A
  # busy or failing service (429/5xx) or one that can't be reached is tried
  # again; any other refusal is reported and the push dropped: the
  # notification is still under the bell. A device refused everything for
  # FORGOTTEN_AFTER is forgotten too, as one the service no longer knows.
  class PushJob < ApplicationJob
    # Kept by the push service while the device is off; after a day it's news no more.
    TTL = 1.day.to_i
    FORGOTTEN_AFTER = 30.days

    BUSY = [ WebPush::TooManyRequests, WebPush::PushServiceError ].freeze
    retry_on(*BUSY, *ApplicationClient::UNREACHABLE, wait: :polynomially_longer, attempts: 5)

    def perform(notification, subscription)
      return unless PushNotifications.enabled? && subscription.profile_id == notification.profile_id

      WebPush.payload_send(
        message: payload(notification, subscription).to_json,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh_key,
        auth: subscription.auth_key,
        vapid: PushNotifications.vapid,
        ttl: TTL,
        urgency: notification.urgent? ? "high" : "normal"
      )
      subscription.update_column(:last_succeeded_at, Time.current)
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      subscription.destroy
    rescue *BUSY
      raise # for retry_on to try again
    rescue WebPush::ResponseError => e
      Rails.error.report(e, handled: true, context: { notification_id: notification.id, subscription_id: subscription.id })
      subscription.destroy if forgotten?(subscription, e)
    end

    private

    # A payload too large is the message's fault, not the device's.
    def forgotten?(subscription, refusal)
      !refusal.is_a?(WebPush::PayloadTooLarge) && (subscription.last_succeeded_at || subscription.created_at) < FORGOTTEN_AFTER.ago
    end

    def payload(notification, subscription)
      routes = Rails.application.routes.url_helpers
      PushPayload.new(notification, subscription, navigate: routes.notification_path(notification), read: routes.notification_read_receipt_path(notification))
    end
  end
end
