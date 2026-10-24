# frozen_string_literal: true

module AssistantEval
  module Checks
    class Stock < Base
      def self.key = "stock"
      def self.argument = "Part of a supply name → quantity left over this profile's purchases"
      def self.example = { "needles" => 99 }

      def call(expected)
        wrong = expected.filter_map do |name, quantity|
          left = SupplyPurchase.where(profile: records.profile).joins(:supply)
            .where("supplies.name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(name.to_s)}%").sum(:quantity_remaining)
          "#{name} #{left.to_f}≠#{quantity}" unless same_number?(left, quantity)
        end
        "stock: #{wrong.join(", ")}" if wrong.any?
      end
    end
  end
end
