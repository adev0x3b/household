# frozen_string_literal: true

module Emails
  # Clears the outbox of what ended long enough ago: sent mail after a week,
  # the budgets reaching back a day at most; failed and dropped mail after
  # a month, for the admin's page (/admin/emails).
  class SweepJob < ApplicationJob
    SENT_KEPT = 7.days
    UNSENT_KEPT = 30.days

    def perform
      OutgoingEmail.sent.where(updated_at: ...SENT_KEPT.ago).in_batches.delete_all
      OutgoingEmail.where(status: %i[failed dropped]).where(updated_at: ...UNSENT_KEPT.ago).in_batches.delete_all
    end
  end
end
