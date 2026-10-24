# frozen_string_literal: true

module Books
  # What one catalogue (Books::OpenLibrary, Books::GoogleBooks) said about an
  # ISBN: the new-book form's attributes, and why there are none when there
  # aren't — :found, :not_found, :unavailable (it couldn't be asked).
  Answer = Data.define(:attributes, :reason) do
    def self.none(reason) = new(attributes: {}, reason: reason)

    def found? = reason == :found
  end
end
