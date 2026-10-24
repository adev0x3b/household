# frozen_string_literal: true

module AssistantEval
  module Checks
    # Changes saved and then undone, so that "nothing left" can't pass just
    # because nothing was ever saved.
    class UndoneChanges < Base
      def self.key = "undone_changes"
      def self.argument = "How many applied changes were undone"
      def self.example = 1

      def call(count)
        undone = Assistant::ChangeSet.where(profile: records.profile, status: :undone).where.not(applied_at: nil).count
        "undone_changes: expected #{count}, got #{undone}" unless undone == count
      end
    end
  end
end
