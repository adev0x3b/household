# frozen_string_literal: true

module AssistantEval
  module Checks
    class GroceryLists < Base
      def self.key = "grocery_lists"
      def self.argument = "How many grocery lists exist"
      def self.example = 1

      def call(count)
        have = records.grocery_lists.count
        "grocery_lists: expected #{count}, got #{have}" unless have == count
      end
    end
  end
end
