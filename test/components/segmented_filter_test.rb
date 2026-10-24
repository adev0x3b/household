# frozen_string_literal: true

require "test_helper"

# A few states to pick one of: a filter revisits the page, a record's state
# is set by a press.
class Components::SegmentedFilterTest < ActiveSupport::TestCase
  ITEMS = [
    Components::NavItem.new(key: "all", href: "/books", label: "All", count: 12),
    Components::NavItem.new(key: "read", href: "/books?status=read", label: "Read", icon: "fa-check", count: 0)
  ].freeze

  test "a filter's pill revisits the page in place, and the current one says so" do
    pills = parse(Components::SegmentedFilter.new(items: ITEMS, current: :read, label: "Status")).css("a.segmented-filter__option")

    assert(pills.all? { _1["data-turbo-action"] == "replace" })
    assert_equal([ nil, "true" ], pills.map { _1["aria-current"] })
    assert_equal(%w[12 0], pills.map { _1.at_css(".segmented-filter__count").text })
  end

  test "with a method each pill sets the record's state instead" do
    pill = parse(Components::SegmentedFilter.new(items: ITEMS, current: "all", label: "Status", method: :patch)).at_css("a")

    assert_equal [ "patch", nil ], [ pill["data-turbo-method"], pill["data-turbo-action"] ]
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(component.call)
end
