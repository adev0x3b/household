# frozen_string_literal: true

class Recipe < ApplicationRecord
  include EditedTogether
  include Searchable
  include Shareable

  searchable_by :name

  belongs_to :profile

  shared_through :recipe_shares

  # The section of the household it belongs to (the share modal's colour).
  def section = :pantry

  has_many :recipe_steps, dependent: :destroy, inverse_of: :recipe
  has_many :recipe_ingredients, dependent: :destroy, inverse_of: :recipe
  has_many :meal_recipes, dependent: :destroy

  accepts_nested_attributes_for :recipe_steps,
                                allow_destroy: true,
                                reject_if: proc { |attrs| attrs["instruction"].blank? }
  accepts_nested_attributes_for :recipe_ingredients,
                                allow_destroy: true,
                                reject_if: proc { |attrs| attrs["ingredient_name"].blank? && attrs["quantity"].blank? }

  reads_typed_names_of :recipe_ingredients
  reads_access_of :recipe_ingredients

  validates :name, presence: true
  validate :recipe_ingredients_have_unique_ingredients

  before_validation :assign_step_positions

  # The person's own and those shared with them.
  scope :accessible_by, ->(profile) {
    where_id_in_any(unscoped.where(profile_id: profile.id).select(:id), RecipeShare.where(profile_id: profile.id).select(:recipe_id))
  }

  # The recipes a meal can be made of: the person's own and those shared
  # with them, by name.
  def self.choices_for(profile) = accessible_by(profile).order(:name)

  private

  # Steps are submitted (and removed) as an unordered nested-attributes
  # batch — renumber the surviving ones from their submission order rather
  # than trust a client-supplied position, which would drift the moment a
  # middle step is deleted.
  def assign_step_positions
    recipe_steps.reject(&:marked_for_destruction?).each.with_index(1) do |step, index|
      step.position = index
    end
  end

  # Mirrors LabTestResult#validate_occurrence (a report's values) — the
  # DB's unique index only catches already-persisted rows, so two new
  # ingredient rows submitted together for the same ingredient both pass the
  # per-record uniqueness validator (neither is in the DB yet).
  def recipe_ingredients_have_unique_ingredients
    active = recipe_ingredients.reject(&:marked_for_destruction?)
    duplicate_ids = active.filter_map(&:ingredient_id).tally.select { |_, count| count > 1 }.keys
    return if duplicate_ids.empty?

    names = Ingredient.where(id: duplicate_ids).pluck(:name)
    errors.add(:recipe_ingredients, :duplicate_ingredients, names: names.join(", "))
  end
end
