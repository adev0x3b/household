# frozen_string_literal: true

require "test_helper"

class Views::Books::RatingTest < ActiveSupport::TestCase
  test "the stars fill up to the rating, out of the most a book can have" do
    assert_equal "★★★☆☆", Views::Books::Rating.stars(3)
    assert_equal "★" * Book::RATINGS.max, Views::Books::Rating.stars(Book::RATINGS.max)
  end

  test "a screen reader hears the rating in words, not the stars" do
    rating = Nokogiri::HTML5.fragment(Views::Books::Rating.new(rating: 4, class_name: "book-card__rating").call).at_css(".book-card__rating")

    assert_equal "true", rating.at_css("[aria-hidden]")["aria-hidden"]
    assert_equal "★★★★☆", rating.at_css("[aria-hidden]").text
    assert_equal I18n.t("books.card.rating", rating: 4), rating.at_css(".is-sr-only").text
    assert_equal I18n.t("books.card.rating", rating: 4), rating["title"]
  end
end
