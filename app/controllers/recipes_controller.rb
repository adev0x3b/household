# frozen_string_literal: true

# The recipes: the index, a recipe's page, and the modal that writes one
# with its steps and ingredients.
class RecipesController < ApplicationController
  include SearchableIndex
  include KeepsWhatWasTyped

  before_action :set_recipe, only: [ :show, :edit, :update, :destroy ]

  def index
    @recipes = index_page(policy_scope(Recipe).search(search_query).includes(:profile, :shared_profiles).order(:name, :id))

    render_searchable_index(
      page: Views::Recipes::Index.new(recipes: @recipes, viewer: current_profile, query: search_query),
      results: Views::Recipes::List.new(recipes: @recipes, viewer: current_profile, query: search_query)
    )
  end

  def show
    authorize @recipe

    render_page Views::Recipes::Show.new(recipe: @recipe, viewer: current_profile, availability: Pantry::Availability.new(current_profile))
  end

  def new
    @recipe = current_profile.recipes.new
    @recipe.recipe_steps.build
    @recipe.recipe_ingredients.build
    authorize @recipe

    render_modal(form_view(@recipe, recipes_path), page: recipes_path)
  end

  def edit
    authorize @recipe

    render_modal(form_view(@recipe, recipe_path(@recipe)), page: @recipe)
  end

  def create
    @recipe = Recipe.new(recipe_params.merge(profile: current_profile))
    authorize @recipe

    if @recipe.save
      redirect_back_after_save(recipe_path(@recipe), notice: t("recipes.notices.created"))
    else
      render turbo_stream: redraw_modal(form_view(@recipe, recipes_path)), status: :unprocessable_content
    end
  end

  def update
    authorize @recipe

    if @recipe.edit_as(current_profile, typed: typed_fields(@recipe, recipe_params)) { @recipe.update(recipe_params) }
      redirect_back_after_save(recipe_path(@recipe), notice: t("recipes.notices.updated"))
    else
      render turbo_stream: redraw_modal(form_view(@recipe, recipe_path(@recipe))), status: :unprocessable_content
    end
  end

  def destroy
    authorize @recipe

    @recipe.destroy!

    redirect_after_destroy(recipe_path(@recipe), list: recipes_path, notice: t("recipes.notices.destroyed"))
  end

  private

  def set_recipe
    @recipe = policy_scope(Recipe).includes(
      :recipe_shares, :shared_profiles,
      recipe_steps: [], recipe_ingredients: [ :ingredient, :unit ]
    ).find(params[:id])
  end

  def recipe_params
    params.expect(recipe: [
                    :name, :description, :lock_version,
                    recipe_steps_attributes: [ [ :id, :instruction, :_destroy ] ],
                    recipe_ingredients_attributes: [ [ :id, :ingredient_name, :unit_name, :quantity, :_destroy ] ]
                  ])
  end

  def form_view(recipe, url)
    Views::Recipes::Modals::Form.new(recipe: recipe, url: url)
  end
end
