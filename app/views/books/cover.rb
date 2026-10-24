# frozen_string_literal: true

# A book's cover (Open Library's by cover id, which isn't rate limited, or
# the URL another source gave) over a stand-in with the title, which shows
# while it loads, when there is none, and when it fails
# (book_cover_controller.js).
# Sizes: "M" on a card, "L" on the book page.
class Views::Books::Cover < Views::Base
  def initialize(book:, size: "M")
    @book = book
    @size = size
  end

  def view_template
    div(class: "book-cover book-cover--#{@size.downcase}", data: ({ controller: "book-cover" } if @book.cover?)) do
      div(class: "book-cover__placeholder", aria: { hidden: "true" }) do
        render Components::Icon.new("fa-book")
        span(class: "book-cover__placeholder-title") { @book.display_title }
      end
      if @book.cover?
        img(src: @book.cover_url(@size), alt: "", loading: "lazy", referrerpolicy: "no-referrer", class: "book-cover__image",
            data: { book_cover_target: "image", action: "error->book-cover#fail" })
      end
    end
  end
end
