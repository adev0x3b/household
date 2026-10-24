# frozen_string_literal: true

module Assistant
  module Operations
    class Update < Base
      # A grocery list's items: lines to add or fix and lines to drop
      # (Assistant::PantryEntries), and lines marked bought or not. A
      # check or uncheck gets an undo entry of its own, since it is
      # reversed by the opposite call, not by restoring columns: checking
      # also moves stock on the ingredient.
      class GroceryItems < Part
        def initialize(record, add:, remove:, check:, uncheck:, context:)
          super(record, profile: context.profile)
          @adds = Array(add)
          @removals = Array(remove).map(&:to_s)
          @checks = Array(check).map(&:to_s)
          @unchecks = Array(uncheck).map(&:to_s)
          @context = context
        end

        def any? = lines_change? || @checks.any? || @unchecks.any?

        # A line whose unit can't be brought into the ingredient's own can't
        # be checked off: said now, not when the set applies.
        def check
          PantryEntries.unconvertible_lines(record, @checks, profile).each do |line|
            problems << "#{line.ingredient.name}: #{line.unit.name} can't be converted to #{line.ingredient.unit.name}, " \
                        "the unit it is kept in — fix the item's unit (items) before checking it off"
          end
        end

        def before
          return {} unless lines_change?

          { items_before: record.grocery_list_items.map { |item| item.slice(:ingredient_id, :unit_id, :quantity, :checked, :checked_at) } }
        end

        # The lines first, then the checks, so a line this same call added
        # or fixed can be checked off too.
        def apply!(_applier)
          if lines_change?
            PantryEntries.apply_items!(record, association: :grocery_list_items, entries: @adds, remove: @removals,
                                               catalog: @context.pantry_catalog_for(record.profile))
          end
          return [] if @checks.empty? && @unchecks.empty?

          result = PantryEntries.apply_checks!(record, check: @checks, uncheck: @unchecks, profile: profile)
          result[:checked].map { |item| entry("item_checked", item) } + result[:unchecked].map { |item| entry("item_unchecked", item) }
        end

        private

        def lines_change? = @adds.any? || @removals.any?
      end
    end
  end
end
