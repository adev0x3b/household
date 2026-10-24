# frozen_string_literal: true

module AssistantEval
  module Checks
    class Purchases < Base
      def self.key = "purchases"
      def self.argument = "How many supply purchases exist"
      def self.example = 3

      def call(count)
        have = records.supply_purchases.count
        "purchases: expected #{count}, got #{have}" unless have == count
      end
    end
  end
end
