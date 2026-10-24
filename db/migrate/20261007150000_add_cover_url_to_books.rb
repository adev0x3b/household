# frozen_string_literal: true

# A cover that isn't Open Library's (Google Books' thumbnail, for the editions
# Open Library doesn't know): kept as its URL next to the Open Library cover id.
class AddCoverUrlToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :cover_url, :string
  end
end
