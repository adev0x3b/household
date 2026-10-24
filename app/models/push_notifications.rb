# frozen_string_literal: true

# Web Push's server identity (VAPID, RFC 8292): the key pair push services
# use to know pushes come from us, read from the environment. In production
# the container makes one on its first boot (bin/docker-secrets); in
# development, `bin/rails push:vapid_keys` prints one for .env. Without one,
# or where the installation turns push off (Platform.push_notifications?,
# the demo), push is off: devices can't subscribe and nothing is sent, the
# bell works as before.
module PushNotifications
  DEFAULT_SUBJECT = "mailto:admin@household.invalid"

  def self.enabled? = Platform.push_notifications? && public_key.present? && private_key.present?

  def self.public_key = ENV["VAPID_PUBLIC_KEY"].presence

  def self.private_key = ENV["VAPID_PRIVATE_KEY"].presence

  def self.vapid
    { subject: ENV["VAPID_SUBJECT"].presence || default_subject, public_key: public_key, private_key: private_key }
  end

  # Who push services may write to about us: the app's host (the Kamal destination's APP_HOST), else a placeholder.
  def self.default_subject = ENV["APP_HOST"].present? ? "mailto:admin@#{ENV["APP_HOST"]}" : DEFAULT_SUBJECT
end
