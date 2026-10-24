# frozen_string_literal: true

# What a change set card row's edit button can open: the edit modal of the
# record a saved row created or updated, and, while a set is still in
# progress, the create modal prefilled with the draft the row would save.
# Only the types that have a modal (a day of a calendar kind, the purchases,
# and a saved collection) can be opened. Assistant::ChangeSets::RowTargets
# reads them for the cards.
module Assistant
  module ChangeSets
    module Review
      MODELS = %w[Occurrence SupplyPurchase IngredientPurchase].freeze
      # The draft kinds whose create modal a set in progress can show.
      KINDS = %w[task transaction appointment medication meal lab_test_result supply_purchase ingredient_purchase].freeze

      # type: the record's route key, which is also its assistant type key
      # (assistant.types.*); record: set for a saved record.
      Target = Data.define(:type, :record, :draft)

      # Saved records whose edit modal a row can open: a collection too,
      # though it has no draft form.
      EDITABLE = (MODELS + %w[Collection]).freeze

      # The undo log kinds of an entry that saved a record's fields.
      SAVED_KINDS = %w[created updated].freeze

      # The one record a saved row is about, from the undo log entries its
      # operation wrote: the main record (a purchase or a visit, not its
      # payment). Nil when it saved several (a bulk "all done") or nothing
      # editable.
      def self.row_record(entries)
        saved = entries.select { |entry| SAVED_KINDS.include?(entry["kind"]) && EDITABLE.include?(entry["model"]) }
          .map { |entry| entry.slice("model", "id", "type") }.uniq
        main = saved.reject { |entry| entry["type"] == Transaction.name }.presence || saved
        main.one? ? main.first.slice("model", "id") : nil
      end

      # Per operation, its position among the creates a draft form can show
      # (nil for the rest), in the order #creates finds them.
      def self.draft_positions(operations)
        position = -1
        operations.map { |op| (position += 1) if op.is_a?(Assistant::Operations::Create) && reviewable?(op.builder) }
      end

      # A day's kind ("lab_test_result"), else the record's own name.
      def self.type_of(record)
        record.is_a?(Occurrence) ? record.event.class.route_key : record.class.name.underscore
      end

      # The unsaved record the nth reviewable create would save, checked as the card would.
      def self.draft_record(set, position)
        builder = creates(set)[position]
        return unless builder

        record = builder.record
        build_cost(record, builder)
        record
      end

      def self.creates(set)
        Compiler.call(set).operations.grep(Assistant::Operations::Create).filter_map(&:builder).select { |builder| reviewable?(builder) }
      end
      private_class_method :creates

      # A kind with a create modal, whose form has somewhere to post to.
      def self.reviewable?(builder)
        builder.present? && KINDS.include?(builder.kind) && builder.form_opens?
      end
      private_class_method :reviewable?

      # The forms read a visit's, meal's or purchase's fee from its cost
      # (Costable#cost / #costs): the draft's, unsaved, answers for itself.
      def self.build_cost(record, builder)
        return unless record.respond_to?(:costs) && builder.cost_requested?

        attributes = builder.cost_attributes
        date = record.is_a?(Occurrence) ? record.date : record.purchased_on
        fee = Transaction.new(profile: builder.profile, starts_on: date, title: record.try(:event_label))
        fee.details.assign_attributes(kind: :expense, amount: attributes["amount"], payment_method: attributes["payment_method"],
                                      currency: attributes["currency"] || builder.profile.household.currency,
                                      counterparty: attributes["counterparty"])
        cost = date ? fee.occurrence_on(date) : Occurrence.new(event: fee)
        record.define_singleton_method(:costs) { [ cost ] }
        record.define_singleton_method(:cost) { cost }
      end
      private_class_method :build_cost
    end
  end
end
