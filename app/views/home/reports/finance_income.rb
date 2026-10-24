# frozen_string_literal: true

# Where the money came from: category breakdown over time and totals.
class Views::Home::Reports::FinanceIncome < Views::Home::Reports::Base
  def self.page = :finance
  def self.report_name = :income

  private

  def icon = "fa-arrow-trend-up"

  def report = @home.finance.income

  def content
    chart(report.by_category_chart)

    render Components::Statistics::DataTable.new(
      caption: t("home.finance.income.category_table_caption"),
      columns: columns(:category, :total, :share, numeric: %i[total share]),
    ) do |table|
      report.category_rows.each do |row|
        table.row do
          table.cell { row.label }
          table.cell { row.money.to_s }
          table.cell { format_figure(row.share, :percent) }
        end
      end
    end
  end
end
