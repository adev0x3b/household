# frozen_string_literal: true

class RecipeStep < ApplicationRecord
  belongs_to :recipe

  validates :instruction, presence: true
end
