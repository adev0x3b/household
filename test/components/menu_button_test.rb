# frozen_string_literal: true

require "test_helper"

# The round "more" button, beside its menu or naming one drawn elsewhere.
class Components::MenuButtonTest < ActiveSupport::TestCase
  test "it says by its label what it shows, and that it is still closed" do
    button = parse(Components::MenuButton.new(label: "More for Dune", data: { action: "click->dropdown#toggle" }))

    assert_equal [ "button", "More for Dune", "More for Dune", "false" ],
                 [ button["type"], button["aria-label"], button["title"], button["aria-expanded"] ]
    assert_nil button["aria-haspopup"]
    assert_equal "click->dropdown#toggle", button["data-action"]
    assert_nil button["aria-controls"], "its menu is beside it"
  end

  test "a button for a menu drawn once for the page names that menu" do
    button = parse(Components::MenuButton.new(label: "More", data: {}, controls: "card_menu"))

    assert_equal "card_menu", button["aria-controls"]
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(ApplicationController.render(component, layout: false)).at_css("button.item-menu__button")
end
