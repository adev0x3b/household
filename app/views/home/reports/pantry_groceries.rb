# frozen_string_literal: true

# What groceries cost over the period, and what was bought most often.
class Views::Home::Reports::PantryGroceries < Views::Home::Reports::Base
  def self.page = :pantry
  def self.report_name = :groceries

  private

  def icon = "fa-cart-shopping"

  def report = @home.pantry.groceries

  def content
    chart(report.spend_chart, empty_message: t("home.pantry.groceries.chart_empty"))

    rows = report.purchase_rows
    return if rows.empty?

    subtitle(:most_bought)
    render Components::Statistics::DataTable.new(
      caption: t("home.pantry.groceries.most_bought"),
      columns: columns(:ingredient, :times, :quantity, numeric: %i[times quantity]),
    ) do |table|
      rows.each do |row|
        table.row do
          table.cell { row.name }
          table.cell { format_figure(row.times, :count) }
          table.cell { quantity_with_unit(row.quantity, row.unit) }
        end
      end
    end
  end
end
