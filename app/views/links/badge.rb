# frozen_string_literal: true

# What waits for the person's answer (Links::Pending), on the drawer's
# Links link and the phone's Menu tab. Links::Broadcaster replaces every
# copy by SELECTOR.
class Views::Links::Badge < Views::Base
  MARKER = "links-badge"
  SELECTOR = ".#{MARKER}"

  def initialize(count:)
    @count = count.to_i
  end

  def view_template
    render Components::CountBadge.new(count: @count, marker: MARKER, label: t("links.index.waiting", count: @count))
  end
end
