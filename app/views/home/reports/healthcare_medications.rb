# frozen_string_literal: true

# Adherence over time, when doses were taken relative to schedule, and a
# per-medication breakdown, worst adherence first.
class Views::Home::Reports::HealthcareMedications < Views::Home::Reports::Base
  def self.page = :healthcare
  def self.report_name = :medications

  private

  def icon = "fa-pills"

  def report = @home.healthcare.medications

  def content
    div(class: "stat-report__charts") do
      chart(report.adherence_chart)
      chart(report.timing_chart, empty_message: t("home.healthcare.medications.timing_empty"))
    end

    render Components::Statistics::DataTable.new(
      caption: t("home.healthcare.medications.table_caption"),
      columns: columns(:name, :taken, :adherence, :streak, :next_dose, numeric: %i[taken adherence streak]),
    ) do |table|
      report.rows.each do |row|
        table.row do
          table.cell { row.name }
          table.cell { t("home.healthcare.medications.taken_of_due", taken: row.taken, due: row.due) }
          table.cell { adherence_cell(row.rate) }
          table.cell { row.streak.to_s }
          table.cell { date(row.next_date) }
        end
      end
    end
  end

  def adherence_cell(rate)
    return plain(format_figure(nil, :percent)) if rate.nil?

    tone = rate >= Reports::Healthcare::Medications::TARGET ? :good : :critical
    render Components::StatusBadge.new(tone: tone, label: format_figure(rate, :percent))
  end
end
