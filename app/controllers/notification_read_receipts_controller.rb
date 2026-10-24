# frozen_string_literal: true

# A notification is read from the bell's row and from the service worker:
# the bell's count everywhere says so, and the reader goes on to what the
# notification is about.
class NotificationReadReceiptsController < ApplicationController
  include FollowsNotifications

  # The service worker reads a tapped push notification and has no page to
  # take a CSRF token from. Another site's POST carries no session cookie
  # (SameSite=Lax), but a sibling subdomain's does: same site isn't same
  # origin. What keeps it harmless is that all this can do is mark one of
  # the viewer's own notifications read.
  skip_forgery_protection

  def create
    notification = policy_scope(Notification).find(params[:notification_id])
    authorize notification, :read?

    notification.mark_read!
    Notifications::Broadcaster.badge(current_profile)
    follow notification, status: :see_other
  end
end
