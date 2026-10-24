# frozen_string_literal: true

# The unread messages, wherever Messages is listed: the drawer and the
# phone's bottom bar. Conversations::Broadcaster replaces every copy by
# SELECTOR over the profile's notifications stream.
class Views::Conversations::Badge < Views::Base
  MARKER = "messages-badge"
  SELECTOR = ".#{MARKER}"

  def initialize(count:)
    @count = count.to_i
  end

  def view_template
    render Components::CountBadge.new(count: @count, marker: MARKER, label: t("conversations.index.unread", count: @count))
  end
end
