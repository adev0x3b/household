# frozen_string_literal: true

# The dropdown's frame: the latest notifications, newest first, and the way
# to older ones. The empty line is always there and shows only while it's
# alone, so a row prepended live (Notifications::Broadcaster) takes its place.
class Views::Notifications::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "notifications-frame"
  LIST_ID = "notifications-list"

  # more: whether older notifications come after these.
  def initialize(notifications:, more:)
    @notifications = notifications
    @more = more
  end

  def view_template
    # Opening a notification leaves the frame for a whole page.
    turbo_frame_tag(FRAME_ID, target: "_top") do
      div(id: LIST_ID, class: "notifications__list") do
        @notifications.each { |notification| render Views::Notifications::Item.new(notification: notification) }
        render Components::EmptyState.new(icon: "fa-bell", message: t("notifications.empty"))
      end
      render Views::Notifications::Older.new(after: @notifications.last, more: @more)
    end
  end
end
