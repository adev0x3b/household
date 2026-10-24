# frozen_string_literal: true

# The agenda's appointments over the period: outcomes per bucket, then
# attendance by kind (work, social…). The attendance rate itself is one of
# the page's headline figures.
class Views::Home::Reports::AgendaAppointments < Views::Home::Reports::Base
  def self.page = :agenda
  def self.report_name = :appointments

  private

  def icon = "fa-user-group"

  def report = @home.agenda.appointments

  def content
    chart(report.outcomes_chart)

    rows = report.kind_rows
    return if rows.empty?

    render Components::Statistics::DataTable.new(
      caption: t("#{scope}.table_caption"),
      columns: columns(:kind, :attended, :attendance, numeric: %i[attended attendance]),
    ) do |table|
      rows.each do |row|
        table.row do
          table.cell { render Components::StatusBadge.new(tone: :neutral, icon: Views::Calendar::Cards::AppointmentCard.kind_icon(row.kind), label: row.kind.label) }
          table.cell { t("#{scope}.attended_of_due", attended: row.attended, due: row.due) }
          table.cell { format_figure(row.rate, :percent) }
        end
      end
    end
  end
end
