# frozen_string_literal: true

require "test_helper"

class BookShareTest < ActiveSupport::TestCase
  test "a book is shared once per person, with a housemate, never with its owner" do
    book = books(:left_hand)

    assert_predicate book.book_shares.build(profile: profiles(:bob)), :valid?
    assert_not book.book_shares.build(profile: profiles(:alice)).valid?

    outsider = book.book_shares.build(profile: profiles(:outsider))
    assert_not outsider.valid?
    assert outsider.errors.of_kind?(:profile, :outside_household)

    book.book_shares.create!(profile: profiles(:bob))
    assert_not book.book_shares.build(profile: profiles(:bob)).valid?
  end
end

class BookshelfShareTest < ActiveSupport::TestCase
  test "a shelf is one per member, shared once per housemate, never with its owner or an outsider" do
    shelf = profiles(:alice).bookshelf!
    assert_equal shelf, profiles(:alice).bookshelf!
    assert_not Bookshelf.new(profile: profiles(:alice)).valid?
    assert_equal "Alice's bookshelf", shelf.name

    assert_predicate shelf.bookshelf_shares.build(profile: profiles(:bob)), :valid?
    assert_not shelf.bookshelf_shares.build(profile: profiles(:alice)).valid?
    outsider = shelf.bookshelf_shares.build(profile: profiles(:outsider))
    assert_not outsider.valid?
    assert outsider.errors.of_kind?(:profile, :outside_household)

    shelf.bookshelf_shares.create!(profile: profiles(:bob))
    assert_not shelf.bookshelf_shares.build(profile: profiles(:bob)).valid?
  end
end
