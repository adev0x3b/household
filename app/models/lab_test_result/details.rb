# frozen_string_literal: true

class LabTestResult
  # Nothing of its own yet: the row exists so every kind has the same shape
  # and a place to grow.
  class Details < ::Details::Base
    self.table_name = "lab_test_result_details"
  end
end
