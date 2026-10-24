# frozen_string_literal: true

# Index/modal will_paginate controls. Renders nothing when there is only one
# page. Pass `turbo_frame:` so page links refresh that frame in place instead
# of navigating away; `turbo_action: "advance"` to keep the URL in step (a
# reload stays on the page). `param_name:` when a page has two paginated
# lists, so each keeps its own page. Short on a phone: the pages beside the
# current one, the first and the last, a gap between (1 2 3 … 12).
# `list:` names the list the pages are of, where a page has more than one,
# so a screen reader's list of landmarks tells the pagers apart.
class Components::Pagination < Components::Base
  register_output_helper :will_paginate

  def initialize(collection:, turbo_frame: nil, turbo_action: nil, param_name: nil, list: nil)
    @collection = collection
    @turbo_frame = turbo_frame
    @turbo_action = turbo_action
    @param_name = param_name
    @list = list
  end

  def view_template
    return unless @collection.respond_to?(:total_pages) && @collection.total_pages > 1

    options = {
      renderer: Components::Pagination::Renderer,
      class: "pagination",
      previous_label: t("pagination.previous"),
      next_label: t("pagination.next"),
      inner_window: 1,
      outer_window: 0
    }
    options[:param_name] = @param_name if @param_name
    options[:list] = @list if @list
    data = { turbo_frame: @turbo_frame.presence, turbo_action: @turbo_action }.compact
    options[:link_attributes] = { data: data } if data.any?

    will_paginate(@collection, options)
  end
end
