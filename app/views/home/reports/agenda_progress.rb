# frozen_string_literal: true

# Tasks done and not done over the period, then task by task.
class Views::Home::Reports::AgendaProgress < Views::Home::Reports::Base
  def self.page = :agenda
  def self.report_name = :progress

  private

  def icon = "fa-chart-column"

  def report = @home.agenda.tasks

  def content
    chart(report.progress_chart, empty_message: t("home.agenda.progress.chart_empty"))

    rows = report.series_rows
    return if rows.empty?

    render Components::Statistics::DataTable.new(
      caption: t("home.agenda.progress.table_caption"),
      columns: columns(:task, :done, :rate, :next, numeric: %i[done rate]),
    ) do |table|
      rows.each do |row|
        table.row do
          table.cell { row.name }
          table.cell { t("home.agenda.progress.done_of_due", done: row.done, due: row.due) }
          table.cell { format_figure(row.rate, :percent) }
          table.cell { date(row.next_date) }
        end
      end
    end
  end
end
