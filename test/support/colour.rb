# frozen_string_literal: true

# A colour as the stylesheet writes it, with the two measures the palette is
# held to: WCAG's contrast ratio against another colour, and the perceptual
# distance between two colours (the straight-line distance in OKLab, times a
# hundred so that about two separates colours a careful eye can just tell
# apart and about ten colours anyone tells apart at a glance).
class Colour
  # How much of the light the eye sees comes from each primary.
  LUMINANCE_WEIGHTS = [ 0.2126, 0.7152, 0.0722 ].freeze

  # OKLab's two matrices: linear light to the responses of the three kinds of
  # cone (long, medium and short wavelengths), and the cube roots of those to
  # lightness, the green-to-red axis and the blue-to-yellow axis.
  CONES = [
    [ 0.4122214708, 0.5363325363, 0.0514459929 ],
    [ 0.2119034982, 0.6806995451, 0.1073969566 ],
    [ 0.0883024619, 0.2817188376, 0.6299787005 ]
  ].freeze
  AXES = [
    [ 0.2104542553, 0.7936177850, -0.0040720468 ],
    [ 1.9779984951, -2.4285922050, 0.4505937099 ],
    [ 0.0259040371, 0.7827717662, -0.8086757660 ]
  ].freeze

  attr_reader :hex

  def self.parse(hex)
    digits = hex.delete_prefix("#")
    digits = digits.chars.map { |digit| digit * 2 }.join if digits.length == 3
    new(hex, digits.scan(/../).map { |channel| channel.hex / 255.0 })
  end

  def initialize(hex, channels)
    @hex = hex
    @channels = channels
  end

  def contrast(other)
    lighter, darker = [ luminance, other.luminance ].sort.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  def distance(other)
    Math.sqrt(oklab.zip(other.oklab).sum { |mine, theirs| (mine - theirs)**2 }) * 100
  end

  # This colour laid over a surface at an opacity, blended channel by channel
  # as a browser draws rgba() on a background: the colour a tint or a wash
  # of it actually shows.
  def over(surface, opacity)
    blended = @channels.zip(surface.channels).map { |mine, theirs| (mine * opacity) + (theirs * (1 - opacity)) }
    Colour.new(format("#%02x%02x%02x", *blended.map { |channel| (channel * 255).round }), blended)
  end

  def to_s = hex

  def luminance = weigh(LUMINANCE_WEIGHTS, linear)

  def oklab
    cones = CONES.map { |weights| Math.cbrt(weigh(weights, linear)) }
    AXES.map { |weights| weigh(weights, cones) }
  end

  protected

  attr_reader :channels

  private

  # sRGB's gamma undone, so that the channels measure light.
  def linear
    @channels.map do |channel|
      channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
    end
  end

  def weigh(weights, values) = weights.zip(values).sum { |weight, value| weight * value }
end
