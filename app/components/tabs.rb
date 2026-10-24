# frozen_string_literal: true

# Switches between the pages of one area (a dashboard's topics, the evals'
# Scenarios and Runs): pill links in a row that scrolls on a narrow screen
# (Components::ScrollRow), the current one marked for assistive technology
# too. Each tab is a Components::NavItem with its `key:` and `icon:`, and
# its `section:` when it opens a section of the household.
#
#   render Components::Tabs.new(label: t("…"), current: :runs, items: [
#     Components::NavItem.new(key: :runs, icon: "fa-clock-rotate-left", href: assistant_evals_runs_path, label: t("…")), …
#   ])
class Components::Tabs < Components::Base
  def initialize(items:, current:, label:)
    @items = items
    @current = current
    @label = label
  end

  def view_template
    render Components::ScrollRow.new do
      nav(class: "tabs-nav", aria: { label: @label }) do
        @items.each { |item| tab(item) }
      end
    end
  end

  private

  def tab(item)
    current = item.key == @current
    a(href: item.href, class: [ "tabs-nav__tab", ("is-current" if current), ("section--#{item.section}" if item.section) ],
      aria: { current: ("page" if current) }) do
      render Components::Icon.new(item.icon)
      span { item.label }
    end
  end
end
