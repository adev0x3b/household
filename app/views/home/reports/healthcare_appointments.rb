# frozen_string_literal: true

# Medical appointments: attendance, outcomes over time, what's next, and
# who we see most (each visit's counterpart: its provider).
class Views::Home::Reports::HealthcareAppointments < Views::Home::Reports::Base
  def self.page = :healthcare
  def self.report_name = :appointments

  private

  def icon = "fa-stethoscope"

  def report = @home.healthcare.appointments

  def content
    attendance_summary
    chart(report.status_chart)
    upcoming_list
    counterpart_table
  end

  def attendance_summary
    metric = report.attendance_metric

    div(class: "stat-inline-metric") do
      span(class: "stat-inline-metric__label") { t("home.healthcare.appointments.attendance") }
      strong(class: "stat-inline-metric__value") { format_figure(metric.value, :percent) }
      render Components::Statistics::DeltaBadge.new(metric: metric)
    end
  end

  def upcoming_list
    upcoming = report.upcoming
    return if upcoming.empty?

    h3(class: "stat-report__subtitle") { t("home.healthcare.appointments.upcoming") }
    ul(class: "stat-list") do
      upcoming.each do |appointment|
        li(class: "stat-list__item") do
          span(class: "stat-list__date") { date(appointment.date) }
          span(class: "stat-list__text") { [ appointment.title, appointment.counterpart ].compact.join(" · ") }
        end
      end
    end
  end

  def counterpart_table
    rows = report.counterpart_rows
    return if rows.empty?

    render Components::Statistics::DataTable.new(
      caption: t("home.healthcare.appointments.table_caption"),
      columns: columns(:counterpart, :attended, :attendance, numeric: %i[attended attendance]),
    ) do |table|
      rows.each do |row|
        table.row do
          table.cell { row.counterpart || t("home.healthcare.appointments.no_counterpart") }
          table.cell { t("home.healthcare.appointments.attended_of_due", attended: row.attended, due: row.due) }
          table.cell { format_figure(row.rate, :percent) }
        end
      end
    end
  end
end
