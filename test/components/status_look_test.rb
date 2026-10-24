# frozen_string_literal: true

require "test_helper"

class Components::StatusLookTest < ActiveSupport::TestCase
  test "a look without an icon of its own takes its tone's" do
    assert_equal "fa-triangle-exclamation", Components::StatusLook.new(tone: :warning).icon
    assert_equal "fa-pause", Components::StatusLook.new(tone: :warning, icon: "fa-pause").icon
  end

  test "a tone there isn't is a mistake when the table is written" do
    assert_raises(ArgumentError) { Components::StatusLook.new(tone: :amber) }
  end

  test "a look under way keeps its tone and turns" do
    look = Components::StatusLook.new(tone: :neutral, icon: "fa-clock").busy

    assert_equal [ :neutral, "fa-spinner fa-spin" ], [ look.tone, look.icon ]
  end

  test "drawn as a pill it is the badge, and as a mark an icon in its tone" do
    look = Components::StatusLook.new(tone: :critical, icon: "fa-circle-xmark")
    badge = Nokogiri::HTML5.fragment(look.badge(label: "Failed", title: "Exit 1").call).at_css(".status-badge")
    mark = Nokogiri::HTML5.fragment(look.mark(label: "Failed", title: "Exit 1").call).at_css("i")

    assert_equal [ "status-badge--critical", "Failed", "Exit 1" ], [ badge.classes.last, badge.text, badge["title"] ]
    assert_equal %w[fa-solid fa-circle-xmark status-tone--critical], mark.classes
    assert_equal [ "img", "Failed", "Exit 1" ], [ mark["role"], mark["aria-label"], mark["title"] ]
  end

  test "a mark without a label is hidden beside the word it stands with" do
    mark = Nokogiri::HTML5.fragment(Components::StatusLook.new(tone: :good).mark.call).at_css("i")

    assert_equal "true", mark["aria-hidden"]
    assert_nil mark["title"]
  end
end
