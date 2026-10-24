# frozen_string_literal: true

# The unread count on the bell, replaced live by Notifications::Broadcaster.
# The bell's own words name it, so the number needs none of its own. The
# installed app's icon follows it (app_badge_controller.js).
class Views::Notifications::Badge < Views::Base
  MARKER = "notifications-badge"
  SELECTOR = ".#{MARKER}"

  def initialize(count:)
    @count = count.to_i
  end

  def view_template
    render Components::CountBadge.new(count: @count, marker: MARKER, data: { controller: "app-badge", app_badge_count_value: @count })
  end
end
