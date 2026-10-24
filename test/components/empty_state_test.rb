# frozen_string_literal: true

require "test_helper"

class Components::EmptyStateTest < ActiveSupport::TestCase
  test "one line says there is nothing, beside an icon for what would be there" do
    empty = Components::EmptyState.new(message: "No runs yet", icon: "fa-clock-rotate-left")
    line = Nokogiri::HTML5.fragment(empty.call).at_css("p.empty-state")

    assert_equal %w[fa-solid fa-clock-rotate-left], line.at_css("i").classes
    assert_equal "true", line.at_css("i")["aria-hidden"]
    assert_equal "No runs yet", line.at_css("span").text
    assert_nil line["id"]
  end

  test "an id names the line a stream takes away" do
    empty = Components::EmptyState.new(message: "No recipes yet", icon: "fa-book-open", id: "recipes_empty")

    assert Nokogiri::HTML5.fragment(empty.call).at_css("p#recipes_empty.empty-state")
  end
end
