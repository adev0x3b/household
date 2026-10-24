# frozen_string_literal: true

# How much of something is done, as a bar: `value` of `max`. Named for
# assistive technology by `label` (the same words shown next to it, e.g.
# "3 of 12 bought"). Full, it turns the success color.
#
#   render Components::ProgressBar.new(value: 3, max: 12, label: t("…", checked: 3, total: 12))
class Components::ProgressBar < Components::Base
  def initialize(value:, max:, label:)
    @value = value
    @max = max
    @label = label
  end

  def view_template
    percent = @max.positive? ? (@value * 100.0 / @max).round.clamp(0, 100) : 0

    div(
      class: [ "progress-bar", ("is-done" if @max.positive? && @value >= @max) ],
      role: "progressbar", aria: { valuenow: @value, valuemin: 0, valuemax: @max, label: @label },
      style: "--progress-bar-value: #{percent}%"
    ) do
      span(class: "progress-bar__fill")
    end
  end
end
