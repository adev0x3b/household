# frozen_string_literal: true

# Creates or updates the one expense paying for something (Costable): a
# day of a series (a visit's fee, a meal out) or a purchase — inferring
# kind, category and currency so callers only pass what a person would
# actually say: amount, payment method, who was paid.
#
# The expense is a one-off Transaction series whose series' row is about
# the day's series (or the purchase) and whose day's row is about the day
# itself, so the fee follows the day it pays for.
#
#   change = Transactions::SetCost.call(
#     visit_day, date: visit_day.date,
#     title: "Visit — Dr. Moretti", amount: "50", payment_method: "card",
#     counterpart: "Moretti", status: :pending
#   )
#   change.cost        # => the Transaction's day (an Occurrence)
#   change.moved_from  # => the date it was on, when this moved it (else nil)
#
# Shared by the appointment, meal, supply-purchase and ingredient-purchase
# forms (Occurrences::FormSave, Purchases::Save) and the assistant.
# Broadcasting is left to the caller (Calendar::DayCardBroadcaster).
#
# What the cost is about may name who it was with (a visit's `counterpart`),
# who becomes the expense's `counterparty`, the one paid.
#
# A currency not given is the one it had, else the household's.
module Transactions
  class SetCost
    Change = Data.define(:cost, :moved_from)

    def self.call(about, date:, title:, amount:, payment_method:, status: :pending, category: :healthcare, currency: nil,
                  counterpart_mode: "text", counterpart: nil, counterparty_profile_id: nil)
      about.materialize! if about.is_a?(Occurrence)
      cost = about.costs.first
      old_date = cost&.date
      series = cost&.event

      if series.nil?
        series = Transaction.new(profile: about.profile, starts_on: date, title: title)
        series.details.assign_attributes(kind: :expense, about: about.is_a?(Occurrence) ? about.event : about)
      end
      series.title = title
      series.starts_on = date
      series.details.assign_attributes(
        category: category, payment_method: payment_method, amount: amount,
        currency: currency.presence || series.details.own_currency.presence || series.profile.household.currency,
        counterparty_mode: counterpart_mode, counterparty: counterpart, counterparty_profile_id: counterparty_profile_id
      )
      series.save!

      cost ||= series.occurrence_on(date)
      cost.date = date
      if cost.new_record?
        cost.status = status
        cost.completed_at = Time.current if status.to_s == "completed"
      end
      cost.save!
      cost.write_details!(about: about) if about.is_a?(Occurrence) && cost.own_details&.about != about

      Change.new(cost: cost, moved_from: (old_date if old_date && old_date != cost.date))
    end
  end
end
