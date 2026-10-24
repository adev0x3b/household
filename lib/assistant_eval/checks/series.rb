# frozen_string_literal: true

module AssistantEval
  module Checks
    class Series < Base
      def self.key = "series"
      def self.argument = "Type → how many series (events) of it are left"
      def self.example = { "medication" => 0 }

      def call(expected)
        wrong = expected.filter_map do |type, count|
          have = records.series(type).count
          "#{type} #{have}≠#{count}" unless have == count.to_i
        end
        "series: #{wrong.join(", ")}" if wrong.any?
      end
    end
  end
end
