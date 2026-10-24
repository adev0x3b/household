# frozen_string_literal: true

class AddSourceEventToEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :events, :source_event, null: true, index: { unique: true }, foreign_key: { to_table: :events }
  end
end
