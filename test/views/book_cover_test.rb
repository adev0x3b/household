# frozen_string_literal: true

require "test_helper"

class Views::Books::CoverTest < ActiveSupport::TestCase
  test "a cover lies over the book's stand-in, which shows if it fails" do
    cover = render_cover(books(:dune))

    assert_equal "book-cover", cover["data-controller"]
    assert_equal "Dune", cover.at_css(".book-cover__placeholder-title").text
    image = cover.at_css("img.book-cover__image")
    assert_equal "image", image["data-book-cover-target"]
    assert_equal "error->book-cover#fail", image["data-action"]
  end

  test "a book with no cover is its stand-in alone" do
    cover = render_cover(Book.new(title: "Untitled draft"))

    assert_nil cover["data-controller"]
    assert_nil cover.at_css("img")
    assert_equal "Untitled draft", cover.at_css(".book-cover__placeholder-title").text
  end

  private

  def render_cover(book) = Nokogiri::HTML5.fragment(Views::Books::Cover.new(book: book).call).at_css(".book-cover")
end
