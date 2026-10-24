# frozen_string_literal: true

require "test_helper"

# The icons the app serves are Font Awesome cut down to the ones its code
# names (FontAwesome::Subset). An icon the code names that the cut lacks
# would show as a blank square, so a new or dropped icon fails here until
# `bin/rails icons:subset` is run again.
class FontAwesomeTest < ActiveSupport::TestCase
  setup do
    @subset = FontAwesome::Subset.new(FontAwesome::NamesInCode.all)
  end

  test "every Font Awesome name in the code is an icon or one of Font Awesome's own classes" do
    assert_empty @subset.unknown, "no such Font Awesome icon or class"
  end

  test "the served stylesheet holds exactly the icons the code names" do
    served = FontAwesome::Subset::TARGET.join(FontAwesome::Subset::STYLESHEET)

    assert_equal @subset.stylesheet, served.read, "#{served.basename} is behind the code: run bin/rails icons:subset"
  end

  test "an icon is kept under the names the code uses, and the others are left out" do
    stylesheet = FontAwesome::Subset.new(%w[fa-check-circle fa-spin]).stylesheet

    assert_includes stylesheet, '.fa-check-circle{--fa:"\f058"}'
    assert_not_includes stylesheet, ".fa-circle-check"
    assert_not_includes stylesheet, ".fa-bell{"
    assert_includes stylesheet, "@keyframes fa-spin"
  end

  test "the fonts keep the named icons' glyphs, and only woff2 is served" do
    subset = FontAwesome::Subset.new(%w[fa-bell fa-check-circle fa-circle-check fa-solid])

    assert_equal %w[f058 f0f3], subset.codepoints
    assert_equal FontAwesome::Subset::FONTS.size, subset.stylesheet.scan("@font-face").size
    assert_not_includes subset.stylesheet, "truetype"
    FontAwesome::Subset::FONTS.each_value do |font|
      assert_includes subset.stylesheet, "url(#{font}.woff2)"
      assert_path_exists FontAwesome::Subset::TARGET.join("#{font}.woff2")
    end
  end

  test "a name the code builds from a style or a typo is caught" do
    assert_equal %w[fa-bel], FontAwesome::Subset.new(%w[fa-bell fa-bel fa-regular]).unknown
  end
end
