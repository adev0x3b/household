# frozen_string_literal: true

module Reports
  module Pantry
    # Things that need someone to act now, whatever period is selected:
    #
    #   :meal_short_on_ingredients   a meal planned that the cook's pantry
    #                                can't cover (Meals#short_rows)
    #   :unrecorded_meal             a meal whose day has passed, still to
    #                                mark, however long ago
    #
    # The meals still to mark are read from Reports::Unfinished, one item a
    # series: its newest such day, counting the others.
    class AttentionItems
      include Enumerable

      def initialize(meals:, today:, window:)
        @meals = meals
        @today = today
        @window = window
      end

      def each(&block) = items.each(&block)

      def items
        @items ||= AttentionItem.sorted(short_meals + unrecorded_meals, today: @today)
      end

      private

      def short_meals
        @meals.short_rows.map do |row|
          AttentionItem.new(
            kind: :meal_short_on_ingredients, severity: :warning, subject: row.title, date: row.date, occurrence: row.occurrence,
            words: { ingredients: row.missing.to_sentence },
          )
        end
      end

      def unrecorded_meals
        @window.unfinished(today: @today).latest(of: Meal).map do |entry, count|
          AttentionItem.new(kind: :unrecorded_meal, resolvable: true, severity: :warning, subject: entry.label, date: entry.date, occurrence: entry.occurrence, count: count)
        end
      end
    end
  end
end
