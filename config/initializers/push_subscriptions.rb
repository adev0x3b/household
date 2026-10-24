# frozen_string_literal: true

# Signing out on a device stops its push notifications: the next person to
# use that phone or browser mustn't get the previous one's. The browser says
# which subscription is its own (PushSubscriptionsController::DEVICE_COOKIE),
# by sign-out's form or by a session that timed out alike.
Warden::Manager.before_logout do |profile, auth, _opts|
  id = auth.request.cookie_jar.signed[PushSubscriptionsController::DEVICE_COOKIE]
  PushSubscription.where(profile_id: profile.id, id: id).delete_all if profile.is_a?(Profile) && id.present?
end
