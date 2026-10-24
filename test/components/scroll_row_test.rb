# frozen_string_literal: true

require "test_helper"

# A row that scrolls sideways is wrapped for its edges to fade.
class Components::ScrollRowTest < ActiveSupport::TestCase
  test "wraps the row it is given, for scroll_hint_controller.js to mark" do
    html = ApplicationController.render(Components::ScrollRow.new { |row| row.nav(class: "tabs-nav") { "tabs" } }, layout: false)
    wrapper = Nokogiri::HTML5.fragment(html).at_css("div.scroll-row[data-controller=scroll-hint]")

    assert_equal "nav", wrapper.first_element_child.name
    assert_equal "tabs-nav", wrapper.first_element_child["class"]
  end

  test "the tabs, a filter's pills and the shelf's genres scroll inside one" do
    tabs = Components::Tabs.new(label: "Pages", current: :a, items: [ Components::NavItem.new(key: :a, icon: "fa-a", href: "/a", label: "A") ])
    filter = Components::SegmentedFilter.new(label: "Status", current: "all", items: [ Components::NavItem.new(key: "all", href: "/x", label: "All") ])

    assert_select_in tabs, ".scroll-row[data-controller=scroll-hint] > nav.tabs-nav a.tabs-nav__tab"
    assert_select_in filter, ".scroll-row[data-controller=scroll-hint] > nav.segmented-filter a.segmented-filter__option"
  end

  private

  def assert_select_in(component, selector)
    html = ApplicationController.render(component, layout: false)
    assert Nokogiri::HTML5.fragment(html).at_css(selector), "expected #{selector} in #{html}"
  end
end
