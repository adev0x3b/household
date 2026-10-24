# frozen_string_literal: true

class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :event, null: false, foreign_key: true
      t.date :occurrence_date, null: false
      t.string :title, null: false
      t.text :description
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, limit: 3
      t.integer :kind, null: false
      t.integer :category, null: false
      t.string :counterparty
      t.integer :payment_method, null: false
      t.integer :status, null: false, default: 0
      t.datetime :completed_at
      t.references :attachable, polymorphic: true
      t.references :attachable_series_event, foreign_key: { to_table: :events }

      t.timestamps
    end

    add_index :transactions, [ :event_id, :occurrence_date ], unique: true
    add_check_constraint :transactions,
                         "amount_cents <> 0",
                         name: "transactions_amount_cents_non_zero"
    add_check_constraint :transactions,
                         "((kind = 0 AND amount_cents > 0) OR (kind = 1 AND amount_cents < 0))",
                         name: "transactions_kind_matches_amount_sign"
    add_check_constraint :transactions,
                         "currency ~ '^[A-Z]{3}$'",
                         name: "transactions_currency_format"
  end
end
