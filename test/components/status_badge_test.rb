# frozen_string_literal: true

require "test_helper"

class Components::StatusBadgeTest < ActiveSupport::TestCase
  test "a tone colors the pill and gives it its icon, beside the word" do
    badge = parse(Components::StatusBadge.new(tone: :warning, label: "Running low"))

    assert_equal %w[status-badge status-badge--warning], badge.classes
    assert_equal %w[fa-solid fa-triangle-exclamation], badge.at_css("i").classes
    assert_equal "Running low", badge.at_css("span").text
  end

  test "a tone there isn't is a mistake, not a grey pill" do
    assert_raises(ArgumentError) { Components::StatusBadge.new(tone: :unheard_of, label: "?") }
    assert_raises(ArgumentError) { Components::StatusBadge.new(tone: "good", label: "?") }
    assert_raises(ArgumentError) { Components::StatusBadge.new(tone: nil, label: "?") }
  end

  test "an icon of its own replaces the tone's, and a title explains the pill" do
    badge = parse(Components::StatusBadge.new(tone: :neutral, label: "Running", icon: "fa-spinner fa-spin", title: "Since 10:02"))

    assert_equal %w[fa-solid fa-spinner fa-spin], badge.at_css("i").classes
    assert_equal "Since 10:02", badge["title"]
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(component.call).at_css(".status-badge")
end
