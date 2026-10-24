# frozen_string_literal: true

module AssistantEval
  module Checks
    # One check on what a scenario left behind. `call` gets the scenario's
    # argument and returns nil when it holds, else a short reason that starts
    # with the check's name. Numbers compare numerically, names ignore case.
    class Base
      class << self
        # The name a scenario's `expect` uses.
        def key = raise(NotImplementedError)
        # What the argument means, for whoever writes a scenario on the eval form.
        def argument = raise(NotImplementedError)
        # An argument the form shows as a placeholder.
        def example = raise(NotImplementedError)
        # About the chat rather than the data: without turns (the null
        # baseline, a replay) there is nothing to judge, so it holds.
        def about_turns? = false
        # Run on every scenario that doesn't switch it off with `false`.
        def on_by_default? = false
      end

      # turns: AssistantEval::Runner::Turn list, nil when only the data is checked.
      def initialize(records, turns)
        @records = records
        @turns = turns
      end

      def call(argument) = raise(NotImplementedError)

      private

      attr_reader :records, :turns

      # Compared as decimals, as the database keeps them, with a comma read as
      # a decimal point. What isn't a number compares as words.
      def same_number?(have, want)
        return false if have.nil?

        number = BigDecimal(have.to_s.tr(",", "."), exception: false)
        wanted = BigDecimal(want.to_s, exception: false)
        number && wanted ? number == wanted : have.to_s.casecmp?(want.to_s)
      end

      # Every word of `name` appears in the record's label (a day's or a
      # series' title, name or counterpart).
      def named?(record, name)
        return true if name.blank?

        details = record.respond_to?(:details) ? record.details : nil
        label = [ record.try(:event_label), record.try(:title), record.try(:name), details.try(:counterpart) ].compact.join(" ").downcase
        name.to_s.downcase.scan(/[[:alnum:]]+/).all? { |word| label.include?(word) }
      end

      # A cost (a Transaction's day): its amount, how it was paid, its category.
      def amount(cost) = cost&.details&.amount
      def paid_with(cost) = cost&.details&.payment_method
      def category_of(cost) = cost&.details&.category
    end
  end
end
