# frozen_string_literal: true

module Assistant
  module Operations
    class Update < Base
      # One kind of change an update carries. A part is built only from what
      # it is given, so Update can check every part before any of them
      # writes, and the undo log learns from each what it must keep.
      class Part
        include UndoEntry

        attr_reader :problems, :notes

        def initialize(record, profile:)
          @record = record
          @profile = profile
          @problems = []
          @notes = []
        end

        # Checks the change against the record, adding to problems and notes.
        # What can't be checked any further raises Failure.
        def check = nil

        # What the undo log keeps from before this part writes, merged into
        # the record's "updated" entry.
        def before = {}

        # Writes the change and returns the undo entries of its own, beyond
        # the record's "updated" one.
        def apply!(_applier) = []

        # Whether it changes the series rather than the day it was asked
        # about: such a change on its own leaves the day as it is.
        def series_level? = false

        private

        attr_reader :record, :profile

        def fail!(message) = raise(Failure, message)

        def day? = record.is_a?(Occurrence)

        # A one-off's fields are its series'; a repeating series' day keeps
        # its own (Occurrences::FormSave#series_scope?).
        def series_scope? = !record.event.recurring?

        def summarize(saved) = Resources.for_record(saved).summarize(saved, profile: profile)

        # A snapshot for the undo log, as plain JSON: a time as "HH:MM".
        def snapshot(row, keys)
          keys.uniq.select { |key| row.has_attribute?(key) }.to_h do |key|
            value = row[key]
            [ key, value.respond_to?(:strftime) && row.type_for_attribute(key).type == :time ? value.strftime("%H:%M") : value.as_json ]
          end
        end

        def details_snapshot(row) = snapshot(row, row.attribute_names - DETAILS_SKIPPED)
      end
    end
  end
end
