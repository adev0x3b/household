# frozen_string_literal: true

# A series' volume number (manga, comics, multi-volume works): the title
# stays the series' name, the number is its own, so "One Piece, vol. 12".
class AddVolumeToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :volume, :integer
  end
end
