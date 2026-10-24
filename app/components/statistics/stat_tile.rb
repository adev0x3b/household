# frozen_string_literal: true

# A headline KPI: label, value, change vs the previous period, and a
# sparkline of the same metric over the period. `footnote` holds context
# the number needs to be read correctly (a target, amounts in other
# currencies). `comparison: false` is for a count as of today (due today,
# items to buy), which has no previous period to be compared with.
class Components::Statistics::StatTile < Components::Base
  def initialize(metric:, label:, icon:, hint:, footnote: nil, comparison: true)
    @metric = metric
    @label = label
    @icon = icon
    @hint = hint
    @footnote = footnote
    @comparison = comparison
  end

  def view_template
    article(class: "stat-tile", aria: { label: @label }) do
      header(class: "stat-tile__header") do
        render Components::Icon.new(@icon, class: "stat-tile__icon")
        h3(class: "stat-tile__label") { @label }
        span(class: "stat-tile__hint", title: @hint, role: "img", aria: { label: @hint }) do
          render Components::Icon.new("fa-circle-question", style: :regular)
        end
      end
      p(class: "stat-tile__value") { format_figure(@metric.value, @metric.format) }
      render Components::Statistics::DeltaBadge.new(metric: @metric) if @comparison
      sparkline if sparkline?
      p(class: "stat-tile__footnote") { @footnote } if @footnote
    end
  end

  private

  def sparkline? = @metric.series.compact.size > 1

  def sparkline
    render Components::Statistics::Chart.new(
      caption: false,
      chart: Reports::Chart.new(
        kind: :sparkline, title: @label, labels: Array.new(@metric.series.size, ""), format: :count,
        series: [ Reports::Chart::Series.new(label: @label, values: @metric.series, color: "series-1") ],
      ),
    )
  end
end
