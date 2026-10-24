# frozen_string_literal: true

# Renders a Reports::Chart: a <canvas> drawn by chart_controller.js from
# the chart's JSON spec, plus the same numbers as a visually hidden <table>
# for screen readers (and anyone who wants the exact values). Empty charts
# render the empty state instead of an empty axis.
class Components::Statistics::Chart < Components::Base
  HEIGHTS = { sparkline: "stat-chart--sparkline", horizontal_bar: "stat-chart--tall" }.freeze

  def initialize(chart:, empty_message: nil, caption: true)
    @chart = chart
    @empty_message = empty_message || t("statistics.empty_chart")
    @caption = caption
  end

  def view_template
    if @chart.empty? && @chart.kind != :sparkline
      return render(Components::EmptyState.new(message: @empty_message, icon: "fa-chart-line"))
    end

    figure(class: [ "stat-chart", HEIGHTS[@chart.kind] ]) do
      figcaption(class: "stat-chart__caption") { @chart.title } if @caption
      div(class: "stat-chart__canvas") do
        canvas(
          role: "img",
          aria: { label: @chart.title },
          data: { controller: "chart", chart_spec_value: @chart.to_spec.to_json },
        )
      end
      data_table unless @chart.kind == :sparkline
    end
  end

  private

  # The hiding class goes on a wrapper, not on the table: a <table> ignores
  # the tiny width .is-sr-only sets and keeps its content's width, and being
  # absolutely positioned it then sticks out of a narrow screen and makes
  # the whole page scroll sideways.
  def data_table
    div(class: "is-sr-only") do
      table do
        caption { @chart.title }
        thead do
          tr do
            # The corner over the rows' names heads no column of its own.
            td
            @chart.series.each { |series| th(scope: "col") { series.label } }
          end
        end
        tbody do
          @chart.labels.each_with_index do |label, index|
            tr do
              th(scope: "row") { label.to_s }
              @chart.series.each { |series| td { cell(series.values[index]) } }
            end
          end
        end
      end
    end
  end

  def cell(value)
    return format_figure(nil, :count) if value.nil?

    format_figure(@chart.point(value), @chart.format)
  end
end
