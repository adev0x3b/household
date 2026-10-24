# frozen_string_literal: true

module Occurrences
  class FormSave
    # A household counts in its own currency, so the form never asks for
    # one: a new payment takes the household's, and a saved one keeps the
    # currency it was made in.
    class Transaction < FormSave
      def self.kind = ::Transaction
      def self.details_fields = %i[amount kind category counterparty counterparty_profile_id counterparty_mode payment_method about_type about_id]

      private

      def build
        super
        event.details.currency = @owner.household.currency if new_series?
      end
    end
  end
end
