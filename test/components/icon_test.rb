# frozen_string_literal: true

require "test_helper"

class Components::IconTest < ActiveSupport::TestCase
  test "an icon beside words is hidden from a screen reader" do
    icon = parse(Components::Icon.new("fa-bell"))

    assert_equal %w[fa-solid fa-bell], icon.classes
    assert_equal "true", icon["aria-hidden"]
    assert_nil icon["role"]
  end

  test "an icon that stands for words of its own is announced by its label" do
    icon = parse(Components::Icon.new("fa-lock", label: "Protected"))

    assert_equal [ "img", "Protected", "Protected" ], attributes(icon, "role", "aria-label", "title")
    assert_nil icon["aria-hidden"]
  end

  test "the regular style, an animation, classes and attributes of the caller's own" do
    icon = parse(Components::Icon.new("fa-spinner fa-spin", style: :regular, class: "uploader__icon", data: { state: "busy" }))

    assert_equal %w[fa-regular fa-spinner fa-spin uploader__icon], icon.classes
    assert_equal "busy", icon["data-state"]
  end

  test "a title of the caller's own stays beside the label" do
    icon = parse(Components::Icon.new("fa-circle-xmark", label: "Failed", title: "The reply named the wrong day"))

    assert_equal [ "Failed", "The reply named the wrong day" ], attributes(icon, "aria-label", "title")
  end

  test "a style Font Awesome is not loaded with is refused" do
    assert_raises(ArgumentError) { Components::Icon.new("fa-github", style: :brands) }
  end

  private

  def parse(component) = Nokogiri::HTML5.fragment(component.call).at_css("i")
  def attributes(element, *names) = names.map { element[_1] }
end
