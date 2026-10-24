# frozen_string_literal: true

# A purchase is kept on its owner's ingredient, so it is that owner's alone.
class IngredientPurchasePolicy < ApplicationPolicy
  def create? = owner?
  def update? = owner?
  def destroy? = owner?
end
