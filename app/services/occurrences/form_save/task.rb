# frozen_string_literal: true

module Occurrences
  class FormSave
    class Task < FormSave
      def self.kind = ::Task
      def self.details_fields = %i[priority]
    end
  end
end
