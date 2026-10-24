# frozen_string_literal: true

module AssistantEval
  module Checks
    # The member must be the payment's counterparty profile, not a name typed
    # into its words.
    class MemberPayment < Base
      def self.key = "member_payment"
      def self.argument = "A payment with a household member (their profile): member, amount, kind"
      def self.example = { "member" => "Marco", "amount" => 50, "kind" => "income" }

      def call(want)
        found = records.days("transaction").to_a.find do |t|
          t.event.details.counterparty_profile&.first_name.to_s.casecmp?(want["member"].to_s) && same_number?(t.details.amount, want["amount"])
        end
        return "member_payment: none with #{want["member"]} for #{want["amount"]}" unless found

        "member_payment: kind #{found.details.kind}, expected #{want["kind"]}" if want["kind"] && found.details.kind != want["kind"].to_s
      end
    end
  end
end
