# frozen_string_literal: true

require "test_helper"

class ColourTest < ActiveSupport::TestCase
  test "white on black is the greatest contrast there is, and a colour on itself the least" do
    white = Colour.parse("#fff")
    black = Colour.parse("#000000")

    assert_in_delta 21.0, white.contrast(black), 0.01
    assert_in_delta 21.0, black.contrast(white), 0.01
    assert_in_delta 1.0, white.contrast(white), 0.001
  end

  test "contrast is WCAG's ratio" do
    assert_in_delta 4.5, Colour.parse("#767676").contrast(Colour.parse("#fff")), 0.05
  end

  test "a colour is no distance from itself, and black is a hundred from white" do
    white = Colour.parse("#ffffff")

    assert_in_delta 0.0, white.distance(white), 0.001
    assert_in_delta 100.0, white.distance(Colour.parse("#000000")), 0.1
  end

  test "distance is perceptual: two greys a step apart are closer than a grey and a red of the same lightness" do
    grey = Colour.parse("#808080")

    assert_operator grey.distance(Colour.parse("#858585")), :<, grey.distance(Colour.parse("#c04040"))
  end

  test "a three-digit hex is read as its six-digit form" do
    assert_in_delta 0.0, Colour.parse("#abc").distance(Colour.parse("#aabbcc")), 0.001
  end
end
