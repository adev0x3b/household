# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A payment. Its own section is its money, so it has no cost section of
    # its own; what it is for, how it was paid and how much are always asked.
    class Transactions < Series
      # A payment said again within a few days is most likely the same one.
      DUPLICATE_WINDOW = 3

      # Money with a household member goes one way or the other: defaulting
      # to an expense would turn "Marco paid me" into the user paying Marco.
      def missing_parts
        parts = super
        if section["counterparty_profile_id"].present? && section["kind"].blank?
          parts << { "field" => "transaction.kind", "problem" => "income if they paid the user, expense if the user paid them" }
        end
        parts
      end

      # The same payee and day with another amount reads as a correction
      # ("it was 80, not 60") rather than a second payment.
      def duplicate_hint(existing)
        repeating = super
        return repeating if repeating || existing["id"].blank? || existing["amount"] == Resources.money(record)

        "An existing payment on the same day, with the same payee (id #{existing["id"]}), is for #{existing["amount"]} — if the " \
          "user is correcting that amount rather than paying twice, use update_record with ref #{existing["id"]} instead of creating a new payment."
      end

      private

      def required_fields = %w[amount category payment_method]

      def normalize(field, value)
        field == "category" ? Normalize.category(value) : super
      end

      def fill_in(event, _given)
        details = event.details
        details.kind ||= "expense"
        details.currency ||= profile.household.currency
        event.title = default_title(event) if event.title.blank?
      end

      # "Marco's half of the rent" (what the user said), else "Housing with
      # Marco" or "Housing": a title is never worth asking for.
      def default_title(transaction)
        return transaction.notes.squish.truncate(80) if transaction.notes.present?

        details = transaction.details
        return if details.category.blank?

        category = I18n.t("transactions.category.#{details.category}")
        person = details.counterparty_profile && Members.new(profile).label(details.counterparty_profile)
        person ||= details.counterparty.presence
        person ? I18n.t("assistant.defaults.payment_title_with", category: category, person: person) : category
      end

      def duplicate_query = record.details.counterparty.presence || record.title
      def duplicate_window = DUPLICATE_WINDOW

      # A payment with a different amount is a correction, left to the
      # softer duplicate_hint: it waits for the button instead of failing.
      def same_day_twin(warnings)
        twin = super
        twin if twin && twin.dig("existing", "amount") == Resources.money(record)
      end
    end
  end
end
