# frozen_string_literal: true

# One device that turned push notifications on (the navbar's "This device"),
# for the profile signed in on it. The endpoint is unique: subscribing the
# same browser for someone else moves it to them, once
# PushSubscriptionsController knows it is the same browser. Removed when the
# push service says it's gone, or has refused every push to it for a month
# (Notifications::PushJob), and when its profile signs out on that device.
class PushSubscription < ApplicationRecord
  belongs_to :profile

  validates :endpoint, :p256dh_key, :auth_key, :origin, presence: true
  validates :endpoint, length: { maximum: 2048 }
  validate :endpoint_is_a_push_service, :origin_is_a_site

  # What the device toggle compares its own endpoint with, without the page
  # holding endpoints (they're bearer capabilities).
  def self.digest(endpoint) = Digest::SHA256.hexdigest(endpoint.to_s)

  # Where a push's link should open: the site this device subscribed on.
  def url_for(path) = URI.join(origin, path).to_s

  private

  # Push services are only ever reached over HTTPS.
  def endpoint_is_a_push_service
    errors.add(:endpoint, :invalid) unless (uri = parse(endpoint)) && uri.scheme == "https" && uri.host.present?
  end

  # Where the device subscribed: a scheme and a host, nothing after them.
  def origin_is_a_site
    uri = parse(origin)
    errors.add(:origin, :invalid) unless uri && %w[http https].include?(uri.scheme) && uri.host.present? && uri.path.blank? && uri.query.nil?
  end

  def parse(url)
    URI.parse(url.to_s)
  rescue URI::InvalidURIError
    nil
  end
end
