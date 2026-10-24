# frozen_string_literal: true

module Assistant
  class DraftBuilder
    class GroceryLists < NamedRecords
      def notes = new_ingredient_names.any? ? [ "new ingredients: #{new_ingredient_names.join(", ")}" ] : []

      private

      def build
        list = GroceryList.new(writable_attributes.merge("profile" => profile))
        pantry_lines("items", GroceryListItem).each { |item| list.grocery_list_items << item }
        list
      end
    end
  end
end
