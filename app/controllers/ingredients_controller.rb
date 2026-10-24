# frozen_string_literal: true

# The pantry's ingredients: the index, and the modal that adds or edits
# one. An ingredient's purchases and their history are
# IngredientPurchasesController's.
class IngredientsController < ApplicationController
  include SearchableIndex

  before_action :set_ingredient, only: [ :edit, :update, :destroy ]

  def index
    @ingredients = index_page(policy_scope(Ingredient).search(search_query).includes(:unit).order(:name, :id))

    render_searchable_index(page: Views::Ingredients::Index.new(ingredients: @ingredients, query: search_query),
                            results: Views::Ingredients::List.new(ingredients: @ingredients, query: search_query))
  end

  def new
    @ingredient = current_profile.ingredients.new
    authorize @ingredient

    render_modal(form_view(@ingredient, ingredients_path), page: ingredients_path)
  end

  def edit
    authorize @ingredient

    render_modal(form_view(@ingredient, ingredient_path(@ingredient)), page: ingredients_path)
  end

  def create
    @ingredient = current_profile.ingredients.new(ingredient_params)
    authorize @ingredient

    if @ingredient.save
      redirect_back_after_save(ingredients_path, notice: t("ingredients.notices.created"))
    else
      render turbo_stream: redraw_modal(form_view(@ingredient, ingredients_path)), status: :unprocessable_content
    end
  end

  def update
    authorize @ingredient

    if @ingredient.update(ingredient_params)
      redirect_back_after_save(ingredients_path, notice: t("ingredients.notices.updated"))
    else
      render turbo_stream: redraw_modal(form_view(@ingredient, ingredient_path(@ingredient))), status: :unprocessable_content
    end
  end

  def destroy
    authorize @ingredient

    if @ingredient.destroy
      redirect_after_destroy(ingredient_path(@ingredient), list: ingredients_path, notice: t("ingredients.notices.destroyed"))
    else
      refuse(t("ingredients.notices.in_use", name: @ingredient.name))
    end
  end

  private

  def set_ingredient
    @ingredient = current_profile.ingredients.find(params[:id])
  end

  def ingredient_params
    params.expect(ingredient: %i[name quantity unit_name category])
  end

  def form_view(ingredient, url)
    Views::Ingredients::Modals::Form.new(ingredient: ingredient, url: url)
  end
end
