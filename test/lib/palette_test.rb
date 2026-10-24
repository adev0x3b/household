# frozen_string_literal: true

require "test_helper"

# The palette's contract, measured on _variables.scss itself so that no
# ratio has to be written beside a colour and kept true by hand: every text
# tone clears AA on each surface it may sit on, every fill clears AA under
# the dark text it takes, every chart mark clears 3:1 on the chart surface,
# and the accents that rest beside one another are far enough apart to be
# told apart at a glance. A colour tuned so that one of these no longer
# holds fails here, naming the pair.
class PaletteTest < ActiveSupport::TestCase
  AA_TEXT = 4.5
  GRAPHIC = 3.0

  # About twice the distance a careful eye can just notice: enough to tell
  # two colours apart without comparing them.
  APART = 10.0

  SURFACES = %w[surface-page surface-sunken surface-card surface-raised].freeze

  # Text that may sit on any surface: the body and secondary text, the pinks,
  # the status text tones, the other accents and the section hues, all of
  # which colour words and icons wherever they appear.
  TEXT_ON_EVERY_SURFACE = %w[
    text text-muted
    accent accent-pressed
    success-text warning-text danger-text
    section-assistant
    section-agenda section-healthcare section-finance section-pantry
  ].freeze

  # The accents that rest on the screen together: the one pink that means
  # "act", the secondary text beside it, the status tones and the section
  # hues. Each must be told apart from every other at a glance.
  RESTING_ACCENTS = %w[
    accent text-muted
    success-text warning-text danger-text
    section-agenda section-healthcare section-finance section-pantry section-assistant
  ].freeze

  # The faintest text (captions, hints, axis ticks) clears AA on the page, a
  # sunken panel and a card, and never sits on the raised surface, where it
  # would fall under.
  LOWER_SURFACES = %w[surface-page surface-sunken surface-card].freeze
  TEXT_ON_LOWER_SURFACES = %w[text-faint].freeze

  # Accents that also fill a pill, a badge or a button, with the sunken
  # surface's colour as the text on them.
  FILLS_WITH_DARK_TEXT = %w[
    accent accent-pressed
    success-text warning-text danger-text
    success-solid warning-solid danger-solid
    section-assistant
  ].freeze

  # The status tones a toast washes the raised surface with, at the tint step
  # _toast.scss names, under body text.
  TOAST_WASHES = %w[success-text warning-text danger-text].freeze
  TOAST_WASH_STEP = "edge"

  # What a chart draws on the chart surface: the series and the status solids.
  CHART_MARKS = %w[
    stat-series-1 stat-series-2 stat-series-3 stat-series-4 stat-series-5 stat-series-6
    success-solid warning-solid danger-solid text-faint
  ].freeze

  SURFACES.each do |surface|
    test "text clears AA on $#{surface}" do
      TEXT_ON_EVERY_SURFACE.each { |text| assert_contrast AA_TEXT, text, surface }
    end
  end

  LOWER_SURFACES.each do |surface|
    test "faint text clears AA on $#{surface}" do
      TEXT_ON_LOWER_SURFACES.each { |text| assert_contrast AA_TEXT, text, surface }
    end
  end

  test "dark text clears AA on every accent used as a fill" do
    FILLS_WITH_DARK_TEXT.each { |fill| assert_contrast AA_TEXT, "surface-sunken", fill }
  end

  test "body text clears AA on a toast washed with each status tone" do
    TOAST_WASHES.each do |tone|
      washed = palette.fetch(tone).over(palette.fetch("surface-raised"), tint_step(TOAST_WASH_STEP))
      ratio = palette.fetch("text").contrast(washed)

      assert_operator ratio, :>=, AA_TEXT,
                      "$text on $surface-raised washed with $#{tone} is #{ratio.round(2)}:1, under #{AA_TEXT}:1"
    end
  end

  test "every chart mark clears 3:1 on the chart surface" do
    CHART_MARKS.each { |mark| assert_contrast GRAPHIC, mark, "stat-surface" }
  end

  test "the resting accents are far enough apart to tell at a glance" do
    RESTING_ACCENTS.combination(2).each do |one, other|
      distance = palette.fetch(one).distance(palette.fetch(other))

      assert_operator distance, :>=, APART, "$#{one} and $#{other} are #{distance.round(1)} apart, under #{APART}"
    end
  end

  test "every colour the contract names is in the stylesheet" do
    named = SURFACES + TEXT_ON_EVERY_SURFACE + TEXT_ON_LOWER_SURFACES + FILLS_WITH_DARK_TEXT + CHART_MARKS +
            RESTING_ACCENTS + %w[stat-surface]

    assert_empty named - palette.keys, "named in the contract, not in _variables.scss"
  end

  private

  def assert_contrast(minimum, foreground, background)
    ratio = palette.fetch(foreground).contrast(palette.fetch(background))

    assert_operator ratio, :>=, minimum,
                    "$#{foreground} on $#{background} is #{ratio.round(2)}:1, under #{minimum}:1"
  end

  # Every colour variable of the stylesheet, a variable set to another
  # variable ($stat-surface) resolved to its colour.
  def palette
    @palette ||= begin
      colours = stylesheet.scan(/^\$([a-z0-9-]+): (#\h{3,6});/).to_h { |name, hex| [ name, Colour.parse(hex) ] }
      aliases = stylesheet.scan(/^\$([a-z0-9-]+): \$([a-z0-9-]+);/).to_h
      colours.merge(aliases.transform_values { |source| colours.fetch(source) })
    end
  end

  # The opacity of one of the stylesheet's tint steps ($tint-steps).
  def tint_step(name)
    stylesheet[/^\s+"#{name}": (0?\.\d+)/, 1].to_f
  end

  def stylesheet
    @stylesheet ||= Rails.root.join("app/assets/stylesheets/_variables.scss").read
  end
end
