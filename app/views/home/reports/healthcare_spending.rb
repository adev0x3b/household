# frozen_string_literal: true

# What the healthcare money went towards over time, per collection (a
# therapy, in Healthcare's words), and the supplies that cost the most in
# this period.
class Views::Home::Reports::HealthcareSpending < Views::Home::Reports::Base
  def self.page = :healthcare
  def self.report_name = :spending

  private

  def icon = "fa-wallet"

  def report = @home.healthcare.spending

  def content
    chart(report.by_type_chart)
    cost_table(:collection, report.collection_rows)
    cost_table(:supply, report.top_supply_rows)
  end

  def cost_table(kind, rows)
    return if rows.empty?

    subtitle(:"#{kind}_title")
    render Components::Statistics::DataTable.new(
      caption: t("home.healthcare.spending.#{kind}_title"),
      columns: columns(kind, :total, :share, numeric: %i[total share]),
    ) do |table|
      rows.each do |row|
        table.row do
          table.cell { row.label.to_s }
          table.cell { row.money.to_s }
          table.cell { format_figure(row.share, :percent) }
        end
      end
    end
  end
end
