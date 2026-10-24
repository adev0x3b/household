# frozen_string_literal: true

# Where the money went: category breakdown over time, the category
# totals, and the largest individual expenses in the period.
class Views::Home::Reports::FinanceSpending < Views::Home::Reports::Base
  def self.page = :finance
  def self.report_name = :spending

  private

  def icon = "fa-wallet"

  def report = @home.finance.spending

  def content
    chart(report.by_category_chart)

    render Components::Statistics::DataTable.new(
      caption: t("home.finance.spending.category_table_caption"),
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

    top_transactions_table
  end

  def top_transactions_table
    rows = report.top_transaction_rows
    return if rows.empty?

    subtitle(:top_transactions_title)
    render Components::Statistics::DataTable.new(
      caption: t("home.finance.spending.top_transactions_title"),
      columns: columns(:date, :title, :category, :amount, numeric: %i[amount]),
    ) do |table|
      rows.each do |row|
        table.row do
          table.cell { date(row.date) }
          table.cell { render(Views::Home::OccurrenceLink.new(occurrence: row.occurrence)) { row.title } }
          table.cell { row.category }
          table.cell { row.money.to_s }
        end
      end
    end
  end
end
