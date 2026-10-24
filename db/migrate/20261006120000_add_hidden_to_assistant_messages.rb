# frozen_string_literal: true

# Messages the model reads but the thread doesn't show: the app's notes to
# the model (a button press, text read from a photo that couldn't be read)
# and a reply the model retried. Kept, never deleted, so the trace stays whole.
class AddHiddenToAssistantMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :assistant_messages, :hidden, :boolean, default: false, null: false
  end
end
