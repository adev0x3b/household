# frozen_string_literal: true

# A whole shelf, shared read-only with a housemate: every book its owner
# has and will add.
class BookshelfShare < ApplicationRecord
  include Share

  shares :bookshelf
end
