# frozen_string_literal: true

# The bell's dropdown: its list (a lazy frame), and a notification's own
# address, where a push notification's tap lands. Reading one, or all of
# them, is a read receipt (NotificationReadReceiptsController,
# NotificationListReadReceiptsController).
class NotificationsController < ApplicationController
  include FollowsNotifications

  # The bell's list, or with `before` the page after that row ("Show
  # older"). The list lives only in the bell's frame: a visit of its own
  # goes home.
  def index
    authorize Notification
    return older if params[:before].present?
    return redirect_to root_path unless turbo_frame_request?

    page = Notifications::BellPage.new(policy_scope(Notification))
    render Views::Notifications::List.new(notifications: page.rows, more: page.more?), layout: false
  end

  # Goes where the notification points and changes nothing: the push
  # notification's link, which the service worker reads first.
  def show
    notification = policy_scope(Notification).find(params[:id])
    authorize notification

    follow notification
  end

  private

  def older
    page = Notifications::BellPage.new(policy_scope(Notification), after: policy_scope(Notification).find(params[:before]))

    render turbo_stream: [
      *page.rows.map { turbo_stream.append(Views::Notifications::List::LIST_ID, Views::Notifications::Item.new(notification: _1)) },
      turbo_stream.replace(Views::Notifications::Older::ID, Views::Notifications::Older.new(after: page.rows.last, more: page.more?))
    ]
  end
end
