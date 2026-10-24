# frozen_string_literal: true

module Assistant
  module Resources
    class Transactions < CalendarResource
      def key = "transaction"
      def type = Transaction
      def search_columns = %i[title notes counterparty]
      def writable = %w[title notes amount currency kind category payment_method counterparty counterparty_profile_id counterparty_mode date]

      def enums
        { "kind" => Transaction::Details.kinds.keys, "category" => Transaction::Details.categories.keys,
          "payment_method" => Transaction::Details.payment_methods.keys }
      end

      # A payment between housemates reads from the viewer's side: what the
      # payer calls an expense is the other's income.
      def summaries(payments, profile)
        members = Members.new(profile)
        payments.map do |payment|
          details = payment.details
          event = payment.event
          theirs = event.counterparty?(profile)
          { title: payment.title, amount: money(payment), kind: theirs ? Transaction::Details.opposite_kind(details.kind) : details.kind,
            category: details.category, payment_method: details.payment_method, paid_to: paid_to(payment, members, theirs),
            for: about_label(event.about_for(payment)) }
        end
      end

      private

      def paid_to(payment, members, theirs)
        event = payment.event
        return members.label(event.profile) if theirs

        member = event.details.counterparty_profile
        payment.details.counterparty.presence || (members.label(member) if member)
      end

      # The other side of each payment and what it pays for, per series.
      def read_for_summaries(payments)
        super
        load(payments.map(&:event).uniq, details: %i[counterparty_profile about])
      end
    end
  end
end
