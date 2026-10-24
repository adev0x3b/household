# frozen_string_literal: true

module Assistant
  module Operations
    # How an operation writes the undo log: what was done to which record.
    # A day is an "Occurrence" with its series' kind as "type"; a series
    # is its Event subclass; the rest their own model.
    module UndoEntry
      private

      def entry(kind, record, **extra)
        base = { "kind" => kind, "model" => record.class.name, "id" => record.id }
        base["type"] = record.event.type if record.is_a?(Occurrence)
        base.merge(extra.stringify_keys)
      end
    end
  end
end
