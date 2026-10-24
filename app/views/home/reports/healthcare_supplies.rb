# frozen_string_literal: true

# How many days each supply lasts at the current pace, and which batches
# expire soon. Always as of today, whatever period is selected.
class Views::Home::Reports::HealthcareSupplies < Views::Home::Reports::Base
  def self.page = :healthcare
  def self.report_name = :supplies

  SEVERITY_LOOKS = {
    critical: Components::StatusLook.new(tone: :critical),
    warning: Components::StatusLook.new(tone: :warning),
    good: Components::StatusLook.new(tone: :good),
    unknown: Components::StatusLook.new(tone: :neutral)
  }.freeze
  EXPIRY_LOOKS = { expired: Components::StatusLook.new(tone: :critical), expiring: Components::StatusLook.new(tone: :warning) }.freeze

  private

  def icon = "fa-box-open"

  def report = @home.healthcare.supplies

  def content
    chart(report.runway_chart, empty_message: t("home.healthcare.supplies.no_rates"))
    runway_table
    expiring_table
  end

  def runway_table
    render Components::Statistics::DataTable.new(
      caption: t("home.healthcare.supplies.table_caption"),
      columns: columns(:supply, :remaining, :days_left, :status, numeric: %i[remaining days_left]),
    ) do |table|
      report.runway_rows.each do |row|
        table.row do
          table.cell { row.supply.name }
          table.cell { quantity_with_unit(row.remaining, row.supply.unit_label) }
          table.cell { row.days_left ? format_figure(row.days_left, :days) : format_figure(nil, :count) }
          table.cell do
            render SEVERITY_LOOKS.fetch(row.severity).badge(label: t("home.healthcare.supplies.severity.#{row.severity}"))
          end
        end
      end
    end
  end

  def expiring_table
    rows = report.expiring_rows
    return if rows.empty?

    subtitle(:expiring_title)
    render Components::Statistics::DataTable.new(
      caption: t("home.healthcare.supplies.expiring_title"),
      columns: columns(:supply, :expires_on, :remaining, numeric: %i[remaining]),
    ) do |table|
      rows.each do |row|
        table.row do
          table.cell { row.supply.name }
          table.cell do
            state = row.expired? ? :expired : :expiring
            render EXPIRY_LOOKS.fetch(state).badge(label: t("home.healthcare.supplies.expiry.#{state}"))
            plain " #{date(row.expires_on)}"
          end
          table.cell { quantity_with_unit(row.remaining, row.supply.unit_label) }
        end
      end
    end
  end
end
