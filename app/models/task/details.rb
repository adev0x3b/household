# frozen_string_literal: true

class Task
  class Details < ::Details::Base
    self.table_name = "task_details"

    enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }

    inherits :priority
    series_requires :priority

    after_initialize { self.priority ||= :low if series? && new_record? }
  end
end
