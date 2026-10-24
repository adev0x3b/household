# frozen_string_literal: true

module AssistantEval
  module Checks
    class Supplies < Base
      def self.key = "supplies"
      def self.argument = "How many supplies the profile has (none added for something it already had)"
      def self.example = 3

      def call(count)
        names = Supply.where(profile: records.profile).pluck(:name)
        "supplies: expected #{count}, got #{names.size} (#{names.join(", ")})" unless names.size == count.to_i
      end
    end
  end
end
