# frozen_string_literal: true

# The bell list's last line while older notifications remain: a link that
# fetches the next page after `after` (NotificationsController#index) and is
# replaced by the next one, or by nothing once the oldest is on the list.
# Then the focus goes to `after`'s row, from which the next Tab reaches the
# rows just added.
class Views::Notifications::Older < Views::Base
  ID = "notifications-older"

  def initialize(after:, more:)
    @after = after
    @more = more
  end

  def view_template
    return unless @more

    a(id: ID, href: notifications_path(before: @after.id), class: "notifications__older",
      data: { turbo_stream: true, focus_fallback: Views::Notifications::Item.button_id(@after) }) do
      t("notifications.older")
    end
  end
end
