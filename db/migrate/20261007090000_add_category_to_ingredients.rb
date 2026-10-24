# frozen_string_literal: true

class AddCategoryToIngredients < ActiveRecord::Migration[8.1]
  def change
    # The store section an ingredient is found in (Ingredient#category), so a
    # grocery list can be walked aisle by aisle. 0 is "other".
    add_column :ingredients, :category, :integer, null: false, default: 0
  end
end
