# frozen_string_literal: true

module AssistantEval
  module Checks
    # Supplies the user didn't mean keep their seeded stock, and no dose
    # plans or draws on them. A change there is the worst a name match can
    # do, someone else's stock drawn, so its reason is marked WRONG_SUPPLY
    # for Lexicon::AgentEval's gate to count.
    class Untouched < Base
      WRONG_SUPPLY = "WRONG SUPPLY"

      def self.key = "untouched"
      def self.argument = "Supply name → its seeded stock: still that much, and no dose uses it (else WRONG SUPPLY)"
      def self.example = { "Siringhe" => 100 }

      def call(expected)
        wrong = expected.filter_map do |name, quantity|
          supply = Supply.find_by(profile: records.profile, name: name.to_s)
          next "#{name} is gone" if supply.nil?

          left = SupplyPurchase.where(supply: supply).sum(:quantity_remaining)
          next "#{name} stock #{left.to_f}≠#{quantity}" unless same_number?(left, quantity)

          "#{name} is used by a dose" if SupplyUse.exists?(supply: supply) || SupplyConsumption.exists?(supply: supply)
        end
        "#{WRONG_SUPPLY}: #{wrong.join(", ")}" if wrong.any?
      end
    end
  end
end
