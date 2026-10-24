# frozen_string_literal: true

# What a household counts its money in: what a payment gets when none is
# said, and what an empty report is shown in. A household's, not
# the app's — a household elsewhere counts in its own. Adding a column with
# a default is metadata only in Postgres 11+, safe beside the running
# version.
class AddCurrencyToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :currency, :string, limit: 3, null: false, default: "EUR"
  end
end
