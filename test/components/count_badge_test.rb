# frozen_string_literal: true

require "test_helper"

class Components::CountBadgeTest < ActiveSupport::TestCase
  test "shows the count, and its words for a screen reader instead of the bare number" do
    badge = parse(Components::CountBadge.new(count: 3, marker: "messages-badge", label: "3 unread messages"))

    assert_equal %w[count-badge messages-badge], badge.classes
    assert_not badge.key?("hidden")
    assert_equal "3", badge.at_css("[aria-hidden=true]").text
    assert_equal "3 unread messages", badge.at_css(".is-sr-only").text
  end

  test "is hidden at zero, so a live update has a place to fill" do
    assert parse(Components::CountBadge.new(count: 0, marker: "links-badge")).key?("hidden")
  end

  test "past ninety-nine it says so rather than growing" do
    assert_equal "99+", parse(Components::CountBadge.new(count: 120, marker: "notifications-badge")).text
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(component.call).at_css(".count-badge")
end
