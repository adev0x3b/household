# frozen_string_literal: true

module Assistant
  module ChangeSets
    # What each row of the change set cards opens (Review::Target), for any
    # number of cards: the records saved rows name are read in one query
    # per kind, not one per row. A saved row opens its record's edit modal;
    # a row of a set still in progress, the create modal of its draft.
    #
    #   targets = Assistant::ChangeSets::RowTargets.load(change_sets)
    #   targets.for(set, row)   # => Review::Target, or nil: nothing to open
    class RowTargets
      # How each kind of record a saved row can open (Review::EDITABLE, as the
      # undo log names them) is read: a day with its series, whose kind
      # names its modal.
      SCOPES = { "Occurrence" => -> { Occurrence.includes(:event) }, "SupplyPurchase" => -> { SupplyPurchase.all },
                 "IngredientPurchase" => -> { IngredientPurchase.all }, "Collection" => -> { Collection.all } }.freeze

      def self.load(sets) = new(Array(sets))

      def initialize(sets)
        @records = read(sets.select(&:applied?).flat_map(&:display).filter_map { _1["review"] })
      end

      def for(set, row)
        review = row["review"]
        return unless review

        if set.applied?
          record = @records[[ review["model"], review["id"].to_i ]]
          Review::Target.new(type: Review.type_of(record), record: record, draft: nil) if record
        elsif set.in_progress? && review["draft"]
          Review::Target.new(type: review["type"], record: nil, draft: review["draft"])
        end
      end

      private

      # { [model name, id] => record }, for the reviews that name a kind with an edit modal.
      def read(reviews)
        reviews.select { SCOPES.key?(_1["model"]) }.group_by { _1["model"] }.flat_map do |model, named|
          SCOPES.fetch(model).call.where(id: named.map { _1["id"] }).map { |record| [ [ model, record.id ], record ] }
        end.to_h
      end
    end
  end
end
