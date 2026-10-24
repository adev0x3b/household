# frozen_string_literal: true

module Assistant
  module Operations
    class Update < Base
      # The record's own fields as the update writes them: a day's
      # (DayFields) or any other record's (RecordFields). Every update has
      # one, with no field in it when the change is something else (a
      # price, a series' repeat), since the undo log's "updated" entry is
      # built from it either way.
      class Fields < Part
        attr_reader :changes

        def initialize(record, changes, enums:, profile:)
          super(record, profile: profile)
          @changes = changes
          @enums = enums
        end

        def empty? = changes.empty?

        # [{ attribute, from, to }] for the owner asked to OK it. Only a day
        # of a linked housemate's series is ever held for that, so a record
        # of any other kind shows nothing.
        def preview_rows = []

        # What writing did that the undo log must know: nothing for most records.
        def outcome = {}

        private

        # An amount written any way, an enum's words, as the record keeps them.
        def normalize!
          changes["amount"] = Normalize.amount(changes["amount"]) if changes.key?("amount")
          @enums.each_key { |field| changes[field] = Normalize.enum(changes[field]) if changes.key?(field) }
        end
      end
    end
  end
end
