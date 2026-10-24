# frozen_string_literal: true

# Change against the previous period, colored by whether the change is good
# for this metric (Metric#trend), not by its sign: fewer missed doses is
# green even though the arrow points down. Carries an arrow and text as
# well as color, so the color is never the only cue.
class Components::Statistics::DeltaBadge < Components::Base
  ARROWS = { up: "fa-arrow-up", down: "fa-arrow-down", flat: "fa-minus" }.freeze

  def initialize(metric:)
    @metric = metric
  end

  def view_template
    text = ::Statistics::Format.delta(@metric)

    if text.nil?
      span(class: "stat-delta stat-delta--none") { t("statistics.delta.no_comparison") }
    else
      span(class: "stat-delta stat-delta--#{@metric.trend}", title: t("statistics.delta.vs_previous")) do
        render Components::Icon.new(ARROWS.fetch(@metric.direction))
        plain " #{text}"
        span(class: "is-sr-only") { " #{t("statistics.delta.vs_previous")}, #{t("statistics.delta.trends.#{@metric.trend}")}" }
      end
    end
  end
end
