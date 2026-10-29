# frozen_string_literal: true

module Profiles
  # What follows every change of a person's password, whichever way it was
  # set (the Account page, a password link). Devise has already signed
  # out every other browser, whose session no longer matches it; this stops
  # what would outlast that: the push notifications those browsers turned on,
  # and their live connections. The browser it was set from keeps its own
  # push (`device`, the subscription it names). The address confirmed now
  # hears of it, even if another takes over before the mail goes. A link to
  # set the password stops working, even one made while it changed, which
  # Devise's own clearing missed, having read the person's row before.
  #
  #   Profiles::AfterPasswordChange.call(profile, device: cookies.signed[PushSubscriptionsController::DEVICE_COOKIE])
  class AfterPasswordChange
    def self.call(profile, device: nil)
      profile.push_subscriptions.where.not(id: device).delete_all
      profile.forget_password_link!
      Emails::Enqueue.call(profile, :password_changed, data: { "to" => profile.email }) if Emails.available_to?(profile)
      Broadcaster.disconnect(profile)
      profile
    end
  end
end
