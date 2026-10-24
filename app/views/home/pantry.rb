# frozen_string_literal: true

# Pantry & meals: what's planned, whether the shelf covers it and what's
# left to buy (as of today), then meals and groceries over the selected
# period, each over its report in Reports::Pantry::Dashboard.
class Views::Home::Pantry < Views::Home::Base
  def self.key = :pantry
  def self.icon = "fa-kitchen-set"

  def self.dashboard(home) = home.pantry

  def self.reports = [ Views::Home::Reports::PantryMeals, Views::Home::Reports::PantryGroceries ]

  private

  def content
    meals = dashboard.meals
    groceries = dashboard.groceries

    attention(dashboard.attention)
    kpi_grid(
      planned: { metric: meals.planned_metric, icon: "fa-utensils", comparison: false },
      eaten: { metric: meals.eaten_metric, icon: "fa-circle-check" },
      open_items: { metric: groceries.open_items_metric, icon: "fa-cart-shopping", comparison: false },
      grocery_spend: { metric: groceries.spend_metric, icon: "fa-wallet", footnote: other_currencies_footnote(groceries) },
    )
    short_meals
    lists
    report_frames
  end

  def short_meals
    rows = dashboard.meals.short_rows

    detail_report(:short_meals, icon: "fa-triangle-exclamation", empty: rows.empty?) do
      render Components::Statistics::DataTable.new(
        caption: t("home.pantry.short_meals.title"), columns: columns(:short_meals, :meal, :day, :missing),
      ) do |table|
        rows.each do |row|
          table.row do
            table.cell { occurrence_link(row) { row.title } }
            table.cell { day(row.date) }
            table.cell { row.missing.to_sentence }
          end
        end
      end
    end
  end

  def lists
    rows = dashboard.groceries.list_rows

    detail_report(:lists, icon: "fa-cart-shopping", empty: rows.empty?) do
      render Components::Statistics::DataTable.new(
        caption: t("home.pantry.lists.title"), columns: columns(:lists, :list, :bought, :left, numeric: %i[bought left]),
      ) do |table|
        rows.each do |row|
          table.row do
            table.cell { a(href: grocery_list_path(row.list)) { row.list.name } }
            table.cell { t("home.pantry.lists.bought", checked: row.checked, total: row.total) }
            table.cell { format_figure(row.open, :count) }
          end
        end
      end
    end
  end
end
