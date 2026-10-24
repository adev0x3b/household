# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # A grocery list item ticked by the set, unticked. Undone by the
      # opposite call, not by restoring its columns: ticking also moves
      # stock on the item's ingredient, and only GroceryListItem#check! and
      # #uncheck! keep that in step.
      class ItemChecked < Step
        private

        def revert(item)
          authorize(item, :uncheck?)
          tick(item)
          GroceryLists::Broadcaster.changed(item.grocery_list)
        end

        def tick(item) = item.uncheck!
      end
    end
  end
end
