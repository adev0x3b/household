# frozen_string_literal: true

module Details
  # An item of a details row's list: a dose's planned supply, a meal's
  # recipe. The callbacks keep a series' done days as they were before the
  # list changes, whoever changes it, and touch what the row describes
  # after, as the row's own fields do.
  module ListItem
    extend ActiveSupport::Concern

    class_methods do
      # `owner` is the item's details row, `as` the list on it the item is in.
      def list_of(owner, as:)
        before_create { public_send(owner).keep_done_days_list!(as) }
        before_update { public_send(owner).keep_done_days_list!(as) if changed? }
        before_destroy { public_send(owner).keep_done_days_list!(as) unless destroyed_by_association }
        after_save { public_send(owner).touch_described if saved_changes? }
        after_destroy { public_send(owner).touch_described unless destroyed_by_association }
      end
    end
  end
end
