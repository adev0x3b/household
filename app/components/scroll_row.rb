# frozen_string_literal: true

# A row that scrolls sideways on a narrow screen (tabs, a filter's pills,
# the shelf's genres), wrapped so that the edge with more behind it fades
# (scroll_hint_controller.js): a chip cut at the edge then reads as "more
# this way", not as cut. What it wraps keeps its own scrolling.
#
#   render Components::ScrollRow.new { nav(class: "tabs-nav") { … } }
class Components::ScrollRow < Components::Base
  def view_template(&)
    div(class: "scroll-row", data: { controller: "scroll-hint" }, &)
  end
end
