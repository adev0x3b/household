# frozen_string_literal: true

# A book's rating as stars, filled up to it. A screen reader hears the
# rating in words, never a row of star characters.
class Views::Books::Rating < Views::Base
  def self.stars(rating) = ("★" * rating) + ("☆" * (Book::RATINGS.max - rating))

  # class_name: the block of whoever shows it ("book-card__rating").
  def initialize(rating:, class_name:)
    @rating = rating
    @class_name = class_name
  end

  def view_template
    span(class: @class_name, title: label) do
      span(aria: { hidden: "true" }) { self.class.stars(@rating) }
      span(class: "is-sr-only") { label }
    end
  end

  private

  def label = t("books.card.rating", rating: @rating)
end
