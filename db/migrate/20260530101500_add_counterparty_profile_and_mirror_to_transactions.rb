# frozen_string_literal: true

class AddCounterpartyProfileAndMirrorToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :transactions, :counterparty_profile, foreign_key: { to_table: :profiles }
    add_reference :transactions, :mirror_transaction, foreign_key: { to_table: :transactions }, index: { unique: true }
  end
end
