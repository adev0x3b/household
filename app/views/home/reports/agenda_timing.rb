# frozen_string_literal: true

# When tasks get done against their day, and how each priority fares.
class Views::Home::Reports::AgendaTiming < Views::Home::Reports::Base
  def self.page = :agenda
  def self.report_name = :timing

  private

  def icon = "fa-stopwatch"

  def report = @home.agenda.tasks

  def any? = report.timed? || report.priority_rows.any?

  def content
    chart(report.timing_chart, empty_message: t("home.agenda.timing.chart_empty"))

    rows = report.priority_rows
    return if rows.empty?

    subtitle(:by_priority)
    render Components::Statistics::DataTable.new(
      caption: t("home.agenda.timing.by_priority"),
      columns: columns(:priority, :done, :rate, numeric: %i[done rate]),
    ) do |table|
      rows.each do |row|
        table.row do
          table.cell { row.priority ? t("tasks.priority.#{row.priority}") : format_figure(nil, :count) }
          table.cell { t("home.agenda.progress.done_of_due", done: row.done, due: row.due) }
          table.cell { format_figure(row.rate, :percent) }
        end
      end
    end
  end
end
