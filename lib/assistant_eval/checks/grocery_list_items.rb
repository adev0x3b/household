# frozen_string_literal: true

module AssistantEval
  module Checks
    class GroceryListItems < Base
      def self.key = "grocery_list_items"
      def self.argument = "Grocery list name → total_items / checked_items"
      def self.example = { "shopping" => { "total_items" => 5, "checked_items" => 2 } }

      def call(expected)
        wrong = expected.filter_map do |key, want|
          list = records.grocery_lists.to_a.find { |l| l.name.downcase.include?(key.to_s.downcase) }
          next "#{key}: no grocery list" if list.nil?

          problems = problems_of(list.grocery_list_items, want)
          "#{key}: #{problems.join(", ")}" if problems.any?
        end
        "grocery_list_items: #{wrong.join("; ")}" if wrong.any?
      end

      private

      def problems_of(items, want)
        problems = []
        if want["total_items"]
          total = items.count
          problems << "total_items #{total}" unless total == want["total_items"].to_i
        end
        if want["checked_items"]
          checked = items.where(checked: true).count
          problems << "checked_items #{checked}" unless checked == want["checked_items"].to_i
        end
        problems
      end
    end
  end
end
