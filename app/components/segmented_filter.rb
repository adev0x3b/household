# frozen_string_literal: true

# A row of pills to pick one of a few states (2–5), each a
# Components::NavItem: a filter on an index (every status, with a count),
# or the state of one record (a book's status). It scrolls on a narrow
# screen (Components::ScrollRow), and the current one is marked for
# assistive technology too.
#
# A filter's pill revisits the page with the filter: a `replace` visit to
# the same path, which Turbo treats as a page refresh (morphed, scroll kept;
# see the layout's turbo-refresh metas), so the navbar's search and buttons
# follow the filter without the reader losing their place. With `method:`
# the pills set the record's state instead, sent by Turbo with that method.
#
#   render Components::SegmentedFilter.new(label: t("…"), current: "reading", items: [
#     Components::NavItem.new(key: "all", href: books_path, label: t("…"), count: 12), …
#   ])
class Components::SegmentedFilter < Components::Base
  def initialize(items:, current:, label:, method: nil)
    @items = items
    @current = current
    @label = label
    @method = method
  end

  def view_template
    render Components::ScrollRow.new do
      nav(class: "segmented-filter", aria: { label: @label }) do
        @items.each { |item| option(item) }
      end
    end
  end

  private

  def option(item)
    current = item.key.to_s == @current.to_s
    a(href: item.href, class: [ "segmented-filter__option", ("is-current" if current) ], aria: { current: ("true" if current) }, data: data) do
      render Components::Icon.new(item.icon) if item.icon
      span(class: "segmented-filter__label") { item.label }
      span(class: "segmented-filter__count") { item.count } unless item.count.nil?
    end
  end

  def data = @method ? { turbo_method: @method } : { turbo_action: "replace" }
end
