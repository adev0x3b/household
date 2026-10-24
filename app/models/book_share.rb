# frozen_string_literal: true

# One book, shared read-only with a housemate.
class BookShare < ApplicationRecord
  include Share

  shares :book
end
