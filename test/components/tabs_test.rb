# frozen_string_literal: true

require "test_helper"

class Components::TabsTest < ActiveSupport::TestCase
  test "the current page is marked, and a section's tab takes its colour" do
    items = [
      Components::NavItem.new(key: :overview, icon: "fa-house", href: "/", label: "Overview"),
      Components::NavItem.new(key: :finance, icon: "fa-sack-dollar", href: "/finance", label: "Finance", section: :finance)
    ]
    tabs = Nokogiri::HTML5.fragment(Components::Tabs.new(label: "Topics", current: :finance, items: items).call).css("a.tabs-nav__tab")

    assert_equal([ nil, "page" ], tabs.map { _1["aria-current"] })
    assert_includes tabs.last.classes, "section--finance"
  end
end
