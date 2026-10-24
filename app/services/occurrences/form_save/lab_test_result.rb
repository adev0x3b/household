# frozen_string_literal: true

module Occurrences
  class FormSave
    class LabTestResult < FormSave
      def self.kind = ::LabTestResult
      def self.child_fields = [ { lab_test_result_entries_attributes: [ %i[id analyte_name unit_name value _destroy] ] } ]
    end
  end
end
