# frozen_string_literal: true

# The Bookshelf section: each member's books, and what sharing needs — a
# bookshelf row per member (what "share my shelf" shares) and the two join
# tables of how-to-share-models (a whole shelf, a single book).
class CreateBookshelf < ActiveRecord::Migration[8.1]
  def change
    create_table :bookshelves do |t|
      t.references :profile, null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end

    create_table :books do |t|
      t.references :profile, null: false, foreign_key: true
      t.string :title, null: false
      t.string :author, null: false
      t.string :isbn, limit: 13                         # 13 digits (Book::Isbn), optional
      t.string :genres, array: true, null: false, default: []
      t.integer :status, null: false, default: 0        # want_to_read
      t.date :started_on
      t.date :finished_on
      t.integer :rating
      t.text :notes
      t.integer :cover_id                               # Open Library cover id, hotlinked
      t.timestamps
    end
    add_index :books, [ :profile_id, :isbn ], unique: true, where: "isbn IS NOT NULL"
    add_index :books, [ :profile_id, :status ]
    add_index :books, :genres, using: :gin

    create_table :book_shares do |t|
      t.references :book, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.timestamps
    end
    add_index :book_shares, [ :book_id, :profile_id ], unique: true

    create_table :bookshelf_shares do |t|
      t.references :bookshelf, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.timestamps
    end
    add_index :bookshelf_shares, [ :bookshelf_id, :profile_id ], unique: true
  end
end
