# frozen_string_literal: true

module Assistant
  module Operations
    # Marks an item skipped, cancelled, in progress or reopened, in the
    # model's words or the user's. Costs are left alone here because
    # Occurrence#change_status! already cancels or reopens them.
    class SetStatus < StatusChange
      STATUS_WORDS = { "done" => "completed", "taken" => "completed", "paid" => "completed", "not_done" => "pending",
                       "open" => "pending", "reopen" => "pending", "skip" => "skipped", "cancel" => "cancelled",
                       "canceled" => "cancelled", "started" => "in_progress", "in progress" => "in_progress" }.freeze

      # "Mark the dose on 24 September 2026 as skipped".
      def summary
        I18n.t("assistant.operations.set_status", thing: label, status: I18n.t("assistant.operations.statuses.#{@status}"))
      end

      private

      def target_status
        word = fields["status"].to_s.downcase.strip
        status = STATUS_WORDS.fetch(word, word.tr(" ", "_"))
        allowed = resource.type.allowed_statuses
        return status if allowed.include?(status)

        fail!("status #{fields["status"].inspect} isn't one a #{type} can have; use one of: #{allowed.join(", ")}")
      end
    end
  end
end
