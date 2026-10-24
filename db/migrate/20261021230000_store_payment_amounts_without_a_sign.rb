# frozen_string_literal: true

# A payment's amount is stored without a sign, and its kind alone says
# which way the money went. A day's row that kept its own amount kept the
# sign of the kind it read then, so the two could disagree once the series
# changed kind; with one fact in one place they can't. Every expense
# stored negative turns positive here.
#
# The version still serving reads the sign and writes it, so this needs
# the app stopped: beside it, every expense would read as an income, and
# a new expense would be refused by the new check.
class StorePaymentAmountsWithoutASign < ActiveRecord::Migration[8.1]
  # Kind 1 is an expense (Transaction::Details.kinds).
  EXPENSE = 1

  def up
    safety_assured do
      remove_check_constraint :transaction_details, name: "transaction_details_kind_matches_amount_sign"
      remove_check_constraint :transaction_details, name: "transaction_details_amount_cents_non_zero"
      execute "UPDATE transaction_details SET amount_cents = -amount_cents WHERE amount_cents < 0"
      add_check_constraint :transaction_details, "amount_cents > 0", name: "transaction_details_amount_cents_positive"
    end
  end

  # Each amount takes the sign of the kind it reads: its row's own, else
  # its series' row's (a series' row joins itself as its own series).
  def down
    safety_assured do
      remove_check_constraint :transaction_details, name: "transaction_details_amount_cents_positive"
      execute(<<~SQL.squish)
        UPDATE transaction_details AS own SET amount_cents = -own.amount_cents
        FROM transaction_details AS series
        WHERE series.event_id = own.event_id AND series.occurrence_id IS NULL
          AND own.amount_cents > 0 AND COALESCE(own.kind, series.kind) = #{EXPENSE}
      SQL
      add_check_constraint :transaction_details, "amount_cents IS NULL OR amount_cents <> 0",
                           name: "transaction_details_amount_cents_non_zero"
      add_check_constraint :transaction_details,
                           "kind IS NULL OR amount_cents IS NULL OR (kind = 0 AND amount_cents > 0) OR (kind = 1 AND amount_cents < 0)",
                           name: "transaction_details_kind_matches_amount_sign"
    end
  end
end
