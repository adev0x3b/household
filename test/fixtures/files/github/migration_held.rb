# frozen_string_literal: true

class FoldEventShares < ActiveRecord::Migration[8.1]
  def up
    safety_assured { rename_table :event_shares, :event_links }
  end
end
