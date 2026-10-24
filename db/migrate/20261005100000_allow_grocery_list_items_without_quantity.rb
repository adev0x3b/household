# frozen_string_literal: true

class AllowGroceryListItemsWithoutQuantity < ActiveRecord::Migration[8.1]
  def change
    change_column_null :grocery_list_items, :quantity, true
  end
end
