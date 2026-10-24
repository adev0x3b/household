# frozen_string_literal: true

# A recipe shared with a housemate, who can change it too.
class RecipeShare < ApplicationRecord
  include Share

  shares :recipe
end
