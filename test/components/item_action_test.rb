# frozen_string_literal: true

require "test_helper"

# One action on one item: a round icon that names what it does, to a
# screen reader and in its tooltip.
class Components::ItemActionTest < ActiveSupport::TestCase
  test "a link names what it does, and its icon is only decoration" do
    action = parse(Components::ItemAction.new(href: "/recipes/1/edit", icon: "fa-pen", label: "Edit Soup", turbo_stream: true)).at_css("a.item-action")

    assert_equal "/recipes/1/edit", action["href"]
    assert_equal [ "Edit Soup", "Edit Soup" ], attributes(action, "aria-label", "title")
    assert action.has_attribute?("data-turbo-stream"), "Turbo asks only whether it is there"
    assert_equal "true", action.at_css("i.fa-solid.fa-pen")["aria-hidden"]
    assert_empty action.text.strip, "the words are its label's, not text beside the icon"
  end

  test "one that changes something says its method to Turbo, asking first, and a destructive one is marked" do
    action = parse(Components::ItemAction.new(href: "/recipes/1", icon: "fa-trash", label: "Delete Soup", method: :delete,
                                              confirm: "Delete Soup?", danger: true)).at_css("a")

    assert_equal %w[item-action item-action--danger], action.classes
    assert_equal [ "delete", "Delete Soup?" ], attributes(action, "data-turbo-method", "data-turbo-confirm")
  end

  test "a download is a form posted outside Turbo, which neither fetches nor prefetches the file" do
    form = parse(Components::ItemAction.new(href: "/files/1/download", icon: "fa-download", label: "Download", download: true)).at_css("form")

    assert_equal [ "/files/1/download", "post", "false" ], attributes(form, "action", "method", "data-turbo")
    assert_equal [ "Download", "Download" ], attributes(form.at_css("button.item-action"), "aria-label", "title")
  end

  test "without a link it is a button a script acts on, never a submit" do
    button = parse(Components::ItemAction.new(icon: "fa-xmark", label: "Remove step", data: { action: "click->nested-fields#remove" })).at_css("button")

    assert_equal [ "button", "Remove step", "click->nested-fields#remove" ], attributes(button, "type", "aria-label", "data-action")
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(ApplicationController.render(component, layout: false))
  def attributes(element, *names) = names.map { element[_1] }
end
