# frozen_string_literal: true

require "test_helper"

# Theme repeats a few colours of _variables.scss for the places a stylesheet
# can't reach. The stylesheet is the source: a colour changed there and not
# here fails this test, naming the variable.
class ThemeTest < ActiveSupport::TestCase
  SOURCE = {
    "PAGE" => "surface-page",
    "SURFACE" => "surface-card",
    "ACCENT" => "accent",
    "ACCENT_PRESSED" => "accent-pressed",
    "TEXT" => "text",
    "MUTED" => "text-muted"
  }.freeze

  test "every colour is the stylesheet's" do
    stylesheet = Rails.root.join("app/assets/stylesheets/_variables.scss").read

    SOURCE.each do |constant, variable|
      expected = stylesheet[/^\$#{variable}: (#\h+);/, 1]

      assert_equal expected, Theme.const_get(constant), "Theme::#{constant} against $#{variable}"
    end
  end

  test "every colour of the theme is accounted for" do
    assert_equal SOURCE.keys.sort, Theme.constants.map(&:to_s).sort
  end
end
