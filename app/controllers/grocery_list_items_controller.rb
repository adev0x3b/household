# frozen_string_literal: true

# The items of a grocery list, kept on the list page itself: added from its
# quick-add bar, edited and removed from their row (ticking one off is
# GroceryListItemChecksController's).
# What is done in place on the list answers with its live regions
# (GroceryListStreams), so the quick-add bar being typed into is never
# drawn again; an edit in its modal revisits the page. Each change is pushed
# to everyone else looking at the list (GroceryLists::Broadcaster).
class GroceryListItemsController < ApplicationController
  include GroceryListStreams
  include KeepsWhatWasTyped

  before_action :set_grocery_list, only: :create
  before_action :set_grocery_list_item, except: :create

  # POST /grocery_lists/:grocery_list_id/grocery_list_items — one typed line
  def create
    parsed = GroceryLists::ParseItem.call(params.dig(:grocery_list_item, :text), unit_names: Unit.accessible_by(current_profile).pluck(:name))
    @grocery_list_item = @grocery_list.grocery_list_items.build(ingredient_name: parsed.name, quantity: parsed.quantity, unit_name: parsed.unit_name)
    authorize @grocery_list_item

    if @grocery_list_item.save
      GroceryLists::Broadcaster.changed(@grocery_list)
      render turbo_stream: grocery_list_region_streams(reload_grocery_list(@grocery_list))
    else
      refuse(create_error) # quick_add_controller.js keeps the text, so it can be corrected
    end
  end

  def edit
    authorize @grocery_list_item

    render_modal(Views::GroceryListItems::Modals::Form.new(item: @grocery_list_item), page: @grocery_list_item.grocery_list)
  end

  def update
    authorize @grocery_list_item

    if @grocery_list_item.edit_as(current_profile, typed: typed_fields(@grocery_list_item, item_params)) { save_with_category }
      GroceryLists::Broadcaster.changed(@grocery_list_item.grocery_list)
      redirect_back_after_save(grocery_list_path(@grocery_list_item.grocery_list),
                               notice: t("grocery_list_items.notices.updated", name: @grocery_list_item.ingredient.name))
    else
      render turbo_stream: redraw_modal(Views::GroceryListItems::Modals::Form.new(item: @grocery_list_item)), status: :unprocessable_content
    end
  end

  def destroy
    authorize @grocery_list_item

    name = @grocery_list_item.ingredient.name
    @grocery_list_item.destroy!
    GroceryLists::Broadcaster.changed(@grocery_list_item.grocery_list)

    render turbo_stream: [
      *grocery_list_region_streams(reload_grocery_list(@grocery_list_item.grocery_list)),
      toast(:success, t("grocery_list_items.notices.removed", name: name))
    ]
  end

  private

  def set_grocery_list
    @grocery_list = policy_scope(GroceryList).includes(:grocery_list_shares).find(params[:grocery_list_id])
  end

  def set_grocery_list_item
    @grocery_list_item = policy_scope(GroceryListItem).includes(
      ingredient: {}, unit: {}, grocery_list: :grocery_list_shares
    ).find(params[:id])
  end

  def item_params
    params.expect(grocery_list_item: %i[quantity unit_name category lock_version])
  end

  # The store section is the ingredient's, so it is saved there, together
  # with the item or not at all.
  def save_with_category
    attrs = item_params
    category = attrs.delete(:category)

    GroceryListItem.transaction do
      @grocery_list_item.ingredient.update!(category: category) if category.present?
      @grocery_list_item.update!(attrs)
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def create_error
    if @grocery_list_item.errors.of_kind?(:ingredient_id, :taken)
      t("grocery_list_items.notices.duplicate", name: @grocery_list_item.ingredient.name)
    else
      @grocery_list_item.errors.full_messages.to_sentence
    end
  end
end
