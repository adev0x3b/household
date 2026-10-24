# frozen_string_literal: true

require "test_helper"

class BookTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @carol = profiles(:carol)
  end

  test "status enum values, in the order the shelf shows them" do
    assert_equal({ "want_to_read" => 0, "reading" => 1, "read" => 2, "dropped" => 3 }, Book.statuses)
    assert_equal Book.statuses.keys.sort, Book::STATUS_ORDER.sort
    assert_equal "want_to_read", Book.new.status
  end

  test "needs a title and an author, squished" do
    book = Book.new(profile: @alice, title: "  ", author: " Ursula   Le Guin ")
    assert_not book.valid?
    assert_includes book.errors[:title], "can't be blank"
    assert_equal "Ursula Le Guin", book.author
  end

  test "the ISBN is stored as 13 digits, once per shelf, or left out" do
    book = Book.create!(profile: @alice, title: "Classic", author: "Someone", isbn: "0-306-40615-2")
    assert_equal "9780306406157", book.isbn

    twice = Book.new(profile: @alice, title: "Again", author: "Someone", isbn: "9780306406157")
    assert_not twice.valid?
    assert_includes twice.errors[:isbn], "is already on your shelf"
    assert_predicate Book.new(profile: @bob, title: "Theirs", author: "Someone", isbn: "9780306406157"), :valid?

    bad = Book.new(profile: @alice, title: "Bad", author: "Someone", isbn: "9780306406158")
    assert_not bad.valid?
    assert_includes bad.errors[:isbn], "isn't a valid ISBN (10 or 13 digits whose check digit adds up)"

    none = Book.create!(profile: @alice, title: "No barcode", author: "Someone", isbn: " ")
    assert_nil none.isbn
    assert_predicate Book.new(profile: @alice, title: "Also none", author: "Someone"), :valid?
  end

  test "genres come as a comma-separated list or an array, cleaned and deduplicated" do
    book = Book.new(profile: @alice, title: "T", author: "A", genre_list: " Fantasy, sci-fi ,, fantasy; Classics ")
    assert_predicate book, :valid?
    assert_equal [ "Fantasy", "sci-fi", "Classics" ], book.genres
    assert_equal "Fantasy, sci-fi, Classics", book.genre_list

    book.genres = [ "History", " history ", "" ]
    assert_equal [ "History" ], book.genres
    book.genres = nil
    assert_equal [], book.genres
    assert_equal [], Book.parse_genres((1..20).map { |n| "g#{n}" }.join(",")).drop(Book::MAX_GENRES)
  end

  test "genre_counts lists what's on a shelf, most used first" do
    assert_equal [ [ "Science fiction", 2 ], [ "Classics", 1 ] ], Book.genre_counts(Book.where(profile: @alice))
  end

  test "starting a book dates it, finishing it too; dates typed by hand win" do
    travel_to Time.zone.local(2026, 10, 7, 10) do
      book = Book.create!(profile: @alice, title: "T", author: "A")
      assert_nil book.started_on

      book.update!(status: :reading)
      assert_equal Date.new(2026, 10, 7), book.started_on
      assert_nil book.finished_on

      book.update!(status: :read)
      assert_equal Date.new(2026, 10, 7), book.finished_on

      book.update!(status: :reading) # read again: a fresh start
      assert_equal Date.new(2026, 10, 7), book.started_on
      assert_nil book.finished_on

      dated = Book.create!(profile: @alice, title: "D", author: "A", status: :read, started_on: Date.new(2026, 1, 1), finished_on: Date.new(2026, 2, 1))
      assert_equal [ Date.new(2026, 1, 1), Date.new(2026, 2, 1) ], [ dated.started_on, dated.finished_on ]

      straight_to_read = Book.create!(profile: @alice, title: "S", author: "A", status: :read)
      assert_equal straight_to_read.finished_on, straight_to_read.started_on

      # Picked up again with the dates typed: those win.
      dated.update!(status: :reading, started_on: Date.new(2026, 9, 1), finished_on: Date.new(2026, 9, 2))
      assert_equal [ Date.new(2026, 9, 1), Date.new(2026, 9, 2) ], [ dated.started_on, dated.finished_on ]
    end
  end

  test "finishing before starting, or a rating off the scale, is refused" do
    book = Book.new(profile: @alice, title: "T", author: "A", started_on: Date.new(2026, 5, 2), finished_on: Date.new(2026, 5, 1))
    assert_not book.valid?
    assert_includes book.errors[:finished_on], "can't be before the day you started"

    assert_not Book.new(profile: @alice, title: "T", author: "A", rating: 6).valid?
    assert_not Book.new(profile: @alice, title: "T", author: "A", rating: 0).valid?
    assert_predicate Book.new(profile: @alice, title: "T", author: "A", rating: 3), :valid?
  end

  test "the cover is credited to where it came from" do
    book = Book.new(profile: @alice, title: "T", author: "A")
    assert_nil book.cover_source

    book.isbn = "9780441478125"
    assert_equal :open_library, book.cover_source, "a book Open Library can look up by its ISBN"

    book.cover_url = "https://books.google.com/books/content?id=x"
    assert_equal :google_books, book.cover_source

    book.cover_id = 8283869
    assert_equal :open_library, book.cover_source, "Open Library's own cover outranks a thumbnail"
  end

  test "a cover URL is one of Google Books' own, over HTTPS: the form sends it back as it likes" do
    book = Book.new(profile: profiles(:alice), title: "Il nome della rosa", author: "Umberto Eco")

    book.cover_url = "https://books.google.com/books/content?id=x&printsec=frontcover&img=1&zoom=1&source=gbs_api"
    assert_predicate book, :valid?

    [ "https://tracker.example/pixel.gif", "http://books.google.com/books/content?id=x", "https://books.google.com.example/x",
      "javascript:alert(1)", "/covers/x.jpg", "https://books.google.com/ x" ].each do |url|
      book.cover_url = url
      assert_not book.valid?, url
      assert book.errors.added?(:cover_url, :invalid), url
    end
  end

  test "accessible_by: one's own, a book shared with them, and the books of a shelf shared with them" do
    assert_equal [ books(:dune), books(:hail_mary), books(:left_hand) ].map(&:id).sort, Book.accessible_by(@alice).pluck(:id).sort
    assert_equal [ books(:hail_mary).id ], Book.accessible_by(@bob).pluck(:id)
    assert_empty Book.accessible_by(@carol)

    @alice.bookshelf!.bookshelf_shares.create!(profile: @carol)
    assert_equal [ books(:dune), books(:left_hand) ].map(&:id).sort, Book.accessible_by(@carol).pluck(:id).sort
    later = Book.create!(profile: @alice, title: "Later", author: "A")
    assert_includes Book.accessible_by(@carol), later
  end

  test "search by title or author, next_status, cover and Open Library links" do
    google = Book.new(cover_url: "https://books.google.com/books/content?id=x&printsec=frontcover&img=1&zoom=1&source=gbs_api")
    assert_equal "https://books.google.com/books/content?id=x&printsec=frontcover&img=1&zoom=1&source=gbs_api", google.cover_url
    assert_equal "https://books.google.com/books/content?id=x&printsec=frontcover&img=1&zoom=1&source=gbs_api&fife=w400", google.cover_url("L")
    assert_predicate google, :cover?
    assert_nil Book.new.cover_url("L")
    assert_equal [ books(:left_hand) ], Book.where(profile: @alice).search("le guin").to_a
    assert_equal [ books(:dune) ], Book.where(profile: @alice).search("dun").to_a

    assert_equal "reading", books(:hail_mary).next_status
    assert_equal "read", books(:left_hand).next_status
    assert_equal "reading", books(:dune).next_status

    assert_equal "https://covers.openlibrary.org/b/id/12345-M.jpg", books(:dune).cover_url
    assert_equal "https://covers.openlibrary.org/b/id/12345-L.jpg", books(:dune).cover_url("L")
    assert_nil books(:left_hand).cover_url
    assert_equal "https://openlibrary.org/isbn/9780441013593", books(:dune).open_library_url
    assert_equal "Dune", books(:dune).name

    books(:dune).update!(volume: 3)
    assert_equal "Dune, vol. 3", books(:dune).display_title
    assert_equal "Dune, vol. 3", books(:dune).name
    assert_not Book.new(profile: @alice, title: "T", author: "A", volume: 0).valid?
  end

  test "removing a book removes its shares" do
    share_id = book_shares(:hail_mary_alice).id
    books(:hail_mary).destroy!
    assert_not BookShare.exists?(share_id)
  end
end
