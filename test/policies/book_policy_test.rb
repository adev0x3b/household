# frozen_string_literal: true

require "test_helper"

class BookPolicyTest < ActiveSupport::TestCase
  def allowed?(user, record, action) = BookPolicy.new(user, record).public_send(action)

  test "the owner does everything; a person it's shared with only looks" do
    book = Book.includes(:book_shares, profile: { bookshelf: :bookshelf_shares }).find(books(:hail_mary).id)

    %i[show? update? destroy? change_status?].each { |action| assert allowed?(profiles(:bob), book, action), action }
    assert allowed?(profiles(:alice), book, :show?)
    %i[update? destroy? change_status?].each { |action| assert_not allowed?(profiles(:alice), book, action), action }
    assert_not allowed?(profiles(:carol), book, :show?)
  end

  test "a shelf shared as a whole opens every book on it, read-only" do
    profiles(:alice).bookshelf!.bookshelf_shares.create!(profile: profiles(:carol))
    book = Book.includes(:book_shares, profile: { bookshelf: :bookshelf_shares }).find(books(:dune).id)

    assert allowed?(profiles(:carol), book, :show?)
    assert_not allowed?(profiles(:carol), book, :update?)
    assert_not allowed?(profiles(:bob), book, :show?)
  end

  test "everyone may list, add, scan and look up" do
    %i[index? create? scan? lookup?].each { |action| assert allowed?(profiles(:carol), Book, action), action }
  end
end
