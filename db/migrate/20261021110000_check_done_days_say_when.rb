# frozen_string_literal: true

# A done day says when it was done, and only a done day does: the
# occurrence validates it, and complete!, uncomplete! and change_status!
# keep it. The database holds a write that goes around them to it too.
#
# Added without checking the rows there are, which would hold a lock on the
# table while the version still serving writes to it; the next migration
# checks them.
class CheckDoneDaysSayWhen < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :occurrences, "(status = 2) = (completed_at IS NOT NULL)",
                         name: "occurrences_completed_at_with_completed", validate: false
  end
end
