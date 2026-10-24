# frozen_string_literal: true

# "Mark all read" on the bell: every notification of the viewer's is read,
# and the count and the list are drawn again where they stand.
class NotificationListReadReceiptsController < ApplicationController
  def create
    authorize Notification, :mark_all_read?

    policy_scope(Notification).unread.update_all(read_at: Time.current)
    Notifications::Broadcaster.badge(current_profile)

    page = Notifications::BellPage.new(policy_scope(Notification))
    render turbo_stream: [
      turbo_stream.replace_all(Views::Notifications::Badge::SELECTOR, Views::Notifications::Badge.new(count: 0)),
      turbo_stream.replace(Views::Notifications::List::FRAME_ID, Views::Notifications::List.new(notifications: page.rows, more: page.more?))
    ]
  end
end
