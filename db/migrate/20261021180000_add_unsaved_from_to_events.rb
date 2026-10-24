# frozen_string_literal: true

# The first day a series' scheduled day may have nothing saved about
# (Event#unsaved_since), so what needs attention reads from there rather
# than from each series' first day. Empty, it reads as the series' first
# day, which is what the version still serving reads, so every series
# keeps today's answer until its next saved day sets it.
class AddUnsavedFromToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :unsaved_from, :date
  end
end
