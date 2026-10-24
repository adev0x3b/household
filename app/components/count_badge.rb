# frozen_string_literal: true

# A count over an icon or after a link's words, hidden at zero. It is
# found by its `marker:` class rather than an id, because the same count
# can be drawn in more than one place and a live update replaces every
# copy at once. `label:` is what a screen reader hears instead of the bare
# number, where the number alone wouldn't say what it counts.
#
#   render Components::CountBadge.new(count: 3, marker: "messages-badge", label: t("conversations.index.unread", count: 3))
class Components::CountBadge < Components::Base
  MAX = 99

  def initialize(count:, marker:, label: nil, data: {})
    @count = count
    @marker = marker
    @label = label
    @data = data
  end

  def view_template
    span(class: [ "count-badge", @marker ], hidden: @count <= 0, data: @data) do
      if @label
        span(aria: { hidden: "true" }) { shown }
        span(class: "is-sr-only") { @label }
      else
        plain shown
      end
    end
  end

  private

  def shown = @count > MAX ? "#{MAX}+" : @count.to_s
end
