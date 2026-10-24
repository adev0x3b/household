# frozen_string_literal: true

module Reports
  module Pantry
    # What is left to buy, and what groceries cost: the completed grocery
    # expenses the viewer reads as such, per currency and never summed
    # across (Reports::TransactionDays). "Items to buy" (unchecked items on
    # active grocery lists) and the lists are as of today, whatever period
    # is selected.
    class Groceries
      PURCHASE_ROWS_LIMIT = 10

      ListRow = Data.define(:list, :total, :checked) do
        def open = total - checked
      end
      PurchaseRow = Data.define(:name, :times, :quantity, :unit)

      def initialize(audience:, period:, window:)
        @audience = audience
        @period = period
        @spend = MoneyFlow.new(
          window.transaction_days,
          period: period, kind: :expense, category: :groceries, fallback_currency: audience.currency,
        )
      end

      def any? = @spend.any? || purchase_rows.any?

      def open_items_metric
        Metric.new(value: list_rows.sum(&:open), format: :count, polarity: :neutral)
      end

      def spend_metric = @spend.metric(polarity: :neutral)

      delegate :other_currencies, to: :@spend

      # Active grocery lists the viewer can open, the ones with most left first.
      def list_rows
        @list_rows ||= begin
          lists = GroceryList.where(id: GroceryList.accessible_by(@audience.viewer).select(:id)).active.order(:name).to_a
          items = GroceryListItem.where(grocery_list_id: lists.map(&:id))
          totals = items.group(:grocery_list_id).count
          checked = items.where(checked: true).group(:grocery_list_id).count

          lists.map { |list| ListRow.new(list: list, total: totals.fetch(list.id, 0), checked: checked.fetch(list.id, 0)) }
            .sort_by { |row| -row.open }
        end
      end

      # Grocery spend per bucket, in the currency most was spent in.
      def spend_chart
        Chart.new(
          kind: :bar, title: I18n.t("home.pantry.groceries.chart"), labels: @period.bucket_labels,
          format: :money, currency: @spend.currency,
          series: [
            Chart::Series.new(label: I18n.t("home.pantry.kpis.grocery_spend"), values: @spend.bucket_amounts)
          ],
        )
      end

      # What was bought most often in the period (purchases and grocery list
      # check-offs alike), with the total quantity in the ingredient's unit.
      def purchase_rows
        @purchase_rows ||= begin
          purchases = IngredientPurchase.where(profile_id: purchaser_ids, purchased_on: @period.range)
          counts = purchases.group(:ingredient_id).count
          quantities = purchases.group(:ingredient_id).sum(:quantity)
          ingredients = Ingredient.includes(:unit).where(id: counts.keys).index_by(&:id)

          counts.sort_by { |ingredient_id, times| [ -times, ingredients[ingredient_id].name ] }.first(PURCHASE_ROWS_LIMIT).map do |ingredient_id, times|
            ingredient = ingredients[ingredient_id]
            PurchaseRow.new(name: ingredient.name, times: times, quantity: quantities[ingredient_id], unit: ingredient.unit&.name)
          end
        end
      end

      private

      # A pantry is its owner's alone, so purchases are the viewer's, unless
      # the page is narrowed to someone else (then there is nothing to show).
      def purchaser_ids
        !@audience.filtered? || @audience.member.id == @audience.viewer.id ? [ @audience.viewer.id ] : []
      end
    end
  end
end
