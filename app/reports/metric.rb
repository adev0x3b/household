# frozen_string_literal: true

module Reports
  # One headline number plus everything a reader needs to judge it: the same
  # number for the previous period, which direction is good, an optional
  # target and the per-bucket series behind its sparkline.
  #
  # `value`/`previous` are Numeric, a Reports::Money, or nil ("not enough
  # data", which is different from 0). `format` picks the renderer
  # (:percent values are 0..100). `polarity` is :higher_is_better,
  # :lower_is_better or :neutral (a change is reported but not judged).
  class Metric < Data.define(:value, :previous, :format, :polarity, :target, :series)
    FORMATS = %i[count percent money days hours].freeze
    POLARITIES = %i[higher_is_better lower_is_better neutral].freeze

    def initialize(value:, format:, polarity:, previous: nil, target: nil, series: [])
      raise ArgumentError, "unknown format #{format}" unless FORMATS.include?(format)
      raise ArgumentError, "unknown polarity #{polarity}" unless POLARITIES.include?(polarity)

      super
    end

    def present? = !value.nil?

    def comparable?
      present? && !previous.nil? && (!value.is_a?(Money) || value.currency == previous.currency)
    end

    # The change: percentage points for :percent, otherwise the same unit
    # as the value (a Money for :money).
    def delta
      value - previous if comparable?
    end

    # :improving, :worsening, :neutral (a change we don't judge) or :flat.
    def trend
      return :flat unless comparable?

      change = delta.to_f
      return :flat if change.zero?
      return :neutral if polarity == :neutral

      (change.positive? == (polarity == :higher_is_better)) ? :improving : :worsening
    end

    def direction
      return :flat unless comparable? && !delta.to_f.zero?

      delta.to_f.positive? ? :up : :down
    end

    def target_met?
      return nil if target.nil? || !present?

      polarity == :lower_is_better ? value <= target : value >= target
    end
  end
end
