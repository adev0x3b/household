# frozen_string_literal: true

# Corrects a recipe's or grocery list's ingredient lines, matching each
# given entry to the line for the same ingredient, and ticks a list's items.
module Assistant
  module PantryEntries
    module_function

    # `association`: :recipe_ingredients or :grocery_list_items.
    def apply_items!(record, association:, entries:, remove: [], catalog:)
      changes = { updated: [], added: [], removed: [] }
      items = record.public_send(association)

      Array(entries).each do |given|
        given = given.to_h
        ingredient = catalog.ingredient(given["ingredient"])
        next unless ingredient

        unit = catalog.unit(given["unit"])
        line = items.find { |item| same_ingredient?(item.ingredient, ingredient) }
        if line
          line.update!({ quantity: given["quantity"], unit: unit }.compact)
          changes[:updated] << ingredient.name
        else
          items.create!(ingredient: ingredient, quantity: given["quantity"], unit: unit)
          changes[:added] << ingredient.name
        end
      end

      Array(remove).each do |name|
        ingredient = catalog.ingredient(name)
        line = ingredient && items.find { |item| same_ingredient?(item.ingredient, ingredient) }
        next unless line

        line.destroy!
        changes[:removed] << line.ingredient.name
      end

      changes.reject { |_, names| names.empty? }
    end

    # Ticking never creates an ingredient: only a line already on the list
    # can be checked off. It returns the items themselves, not their names,
    # because each one gets its own undo entry.
    def apply_checks!(list, check: [], uncheck: [], profile:)
      checked = Array(check).filter_map { |name| find_line(list, name, profile) }.each(&:check!)
      unchecked = Array(uncheck).filter_map { |name| find_line(list, name, profile) }.each(&:uncheck!)
      { checked: checked, unchecked: unchecked }
    end

    # Lines whose unit can't be brought into the ingredient's own (2 pcs of
    # something kept in kg). Checking them off would be refused, so the
    # update says so before it starts. A line with no quantity buys nothing
    # when checked, so it has nothing to convert.
    def unconvertible_lines(list, names, profile)
      Array(names).filter_map { |name| find_line(list, name, profile) }.select do |item|
        item.quantity && Unit.convert(item.quantity, item.unit, item.ingredient.unit).nil?
      end
    end

    def same_ingredient?(a, b)
      a.persisted? && b.persisted? ? a.id == b.id : a.name.casecmp?(b.name)
    end

    def find_line(list, name, profile)
      ingredient = NameMatch.find(profile.ingredients, name)
      list.grocery_list_items.find { |item| item.ingredient_id == ingredient.id } if ingredient
    end
  end
end
