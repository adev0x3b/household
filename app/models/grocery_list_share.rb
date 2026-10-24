# frozen_string_literal: true

# A grocery list shared with a housemate, who can change it and shop from it.
class GroceryListShare < ApplicationRecord
  include Share

  shares :grocery_list
end
