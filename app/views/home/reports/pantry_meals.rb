# frozen_string_literal: true

# Meals eaten against the plan over the period, then by kind of meal.
class Views::Home::Reports::PantryMeals < Views::Home::Reports::Base
  def self.page = :pantry
  def self.report_name = :meals

  private

  def icon = "fa-utensils"

  def report = @home.pantry.meals

  def content
    chart(report.outcomes_chart)

    rows = report.meal_type_rows
    return if rows.empty?

    render Components::Statistics::DataTable.new(
      caption: t("home.pantry.meals.table_caption"),
      columns: columns(:meal_type, :eaten, :rate, numeric: %i[eaten rate]),
    ) do |table|
      rows.each do |row|
        table.row do
          table.cell { row.meal_type ? t("meals.meal_type.#{row.meal_type}") : format_figure(nil, :count) }
          table.cell { t("home.pantry.meals.eaten_of_due", eaten: row.eaten, due: row.due) }
          table.cell { format_figure(row.rate, :percent) }
        end
      end
    end
  end
end
