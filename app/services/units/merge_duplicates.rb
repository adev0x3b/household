# frozen_string_literal: true

# Folds a group of one unit spelled differently (Units::Duplicates) into the
# row it keeps: everything that names the others moves to it, and it takes
# the canonical spelling. A range that would collide with one the kept unit
# already has for the same analyte and sex is left where it is (and its
# unit kept) — reported, never overwritten.
#
#   merged = Units::MergeDuplicates.call(group)
#   merged.rows, merged.ranges   # how many moved
#   merged.collisions            # the ranges left where they were
module Units
  class MergeDuplicates
    Merged = Data.define(:group, :rows, :ranges, :collisions)

    # Everything that names a unit, but the reference ranges, which can
    # collide and so move one at a time.
    USES = [ LabTestResultEntry, Ingredient, IngredientPurchase, RecipeIngredient, GroceryListItem ].freeze

    def self.call(group)
      rows = ranges = 0
      collisions = []
      Unit.transaction do
        group.others.each do |other|
          rows += USES.sum { |uses| uses.where(unit: other).update_all(unit_id: group.keep.id) }
          ReferenceRange.where(unit: other).find_each do |range|
            if ReferenceRange.exists?(analyte_id: range.analyte_id, unit_id: group.keep.id, sex: range.sex)
              collisions << range
            else
              range.update!(unit: group.keep)
              ranges += 1
            end
          end
          other.destroy! unless collisions.any? { |range| range.unit_id == other.id }
        end
        group.keep.update!(name: group.name) if group.keep.name != group.name && !Unit.where(household_id: group.keep.household_id).where.not(id: group.keep.id).exists?([ "LOWER(name) = ?", group.name.downcase ])
      end
      Merged.new(group: group, rows: rows, ranges: ranges, collisions: collisions)
    end
  end
end
