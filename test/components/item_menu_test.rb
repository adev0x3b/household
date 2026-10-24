# frozen_string_literal: true

require "test_helper"

# The rest of an item's actions, behind one "more" button.
class Components::ItemMenuTest < ActiveSupport::TestCase
  ACTIONS = [
    Components::Action.new(href: "/books/1", icon: "fa-trash", label: "Delete", method: :delete, confirm: "Sure?", danger: true),
    Components::Action.new(href: "/books/1/edit", icon: "fa-pen", label: "Edit", turbo_stream: true),
    Components::Action.new(href: "/books/1/download", icon: "fa-download", label: "Download", download: true)
  ].freeze

  test "its button names the menu and says it is closed; the entries are plain links and buttons, reached by Tab" do
    menu = parse(Components::ItemMenu.new(label: "More for Dune", actions: ACTIONS))
    button = menu.at_css("button.item-menu__button")

    assert_equal [ "More for Dune", "false" ], attributes(button, "aria-label", "aria-expanded")
    assert_nil button["aria-haspopup"], "a disclosure, not an ARIA menu, whose arrow keys it doesn't have"
    assert_empty menu.css("[role]")
  end

  test "what destroys comes last, set apart, whatever order it was given in" do
    entries = parse(Components::ItemMenu.new(label: "More", actions: ACTIONS)).css(".item-menu__entry")

    assert_equal(%w[Edit Download Delete], entries.map { _1.text.strip })
    assert_includes entries.last.classes, "item-menu__entry--danger"
    assert_equal [ "/books/1", "delete", "Sure?" ], attributes(entries.last, "href", "data-turbo-method", "data-turbo-confirm")
  end

  test "a download is a form's button, posted outside Turbo" do
    form = parse(Components::ItemMenu.new(label: "More", actions: ACTIONS)).at_css("form")

    assert_equal [ "/books/1/download", "false" ], attributes(form, "action", "data-turbo")
    assert_equal "Download", form.at_css("button.item-menu__entry").text.strip
  end

  test "an entry folds the menu when chosen, so a question it asks isn't answered over the open menu" do
    entries = parse(Components::ItemMenu.new(label: "More", actions: ACTIONS)).css(".item-menu__entry")

    assert(entries.all? { _1["data-action"] == "click->dropdown#close" })
  end

  test "nothing more to do, no button" do
    assert_empty Components::ItemMenu.new(label: "More", actions: []).call
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(ApplicationController.render(component, layout: false))
  def attributes(element, *names) = names.map { element[_1] }
end
