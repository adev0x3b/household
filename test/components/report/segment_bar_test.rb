# frozen_string_literal: true

require "test_helper"

class Components::Report::SegmentBarTest < ActiveSupport::TestCase
  test "one segment per step in its tone, named as a whole" do
    bar = Nokogiri::HTML5.fragment(Components::Report::SegmentBar.new(segments: %i[good warning neutral], label: "1 of 3 steps done").call).at_css("div")

    assert_equal [ "img", "1 of 3 steps done" ], [ bar["role"], bar["aria-label"] ]
    assert_equal(%w[good warning neutral], bar.css("span").map { _1.classes.last.delete_prefix("report-segments__segment--") })
  end

  test "a tone there isn't is a mistake, not a grey segment" do
    assert_raises(ArgumentError) { Components::Report::SegmentBar.new(segments: %i[good amber], label: "?") }
  end
end
