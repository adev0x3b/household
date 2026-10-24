# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # A grocery list item unticked by the set, ticked again.
      class ItemUnchecked < ItemChecked
        private

        def tick(item) = item.check!
      end
    end
  end
end
