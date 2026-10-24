# frozen_string_literal: true

# A device can be subscribed by whoever is signed in on it, where push is on
# (PushNotifications: VAPID keys, and not turned off by the installation —
# the demo's accounts are everyone's, so a stranger's phone would get the
# next visitor's notifications). Only one's own can be removed.
class PushSubscriptionPolicy < ApplicationPolicy
  def create? = PushNotifications.enabled?
  def destroy? = owner?
  def update? = destroy? && create?
end
