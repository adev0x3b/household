# frozen_string_literal: true

# An item's check: put there by a tap on its row, which buys the item and
# restocks the ingredient, and taken away by the next. A tap says which
# state it wants rather than "the other one", so two housemates ticking the
# same item, or a page that was out of date, leave it as asked. The list's
# regions answer (GroceryListStreams), and everyone else looking at the
# list hears of it (GroceryLists::Broadcaster).
class GroceryListItemChecksController < ApplicationController
  include GroceryListStreams

  before_action do
    @grocery_list_item = policy_scope(GroceryListItem).includes(ingredient: {}, unit: {}, grocery_list: :grocery_list_shares)
      .find(params[:grocery_list_item_id])
  end

  def create
    authorize @grocery_list_item, :check?

    begin
      @grocery_list_item.edited_by(current_profile).check!
    rescue ActiveRecord::RecordInvalid => e
      return refuse(e.record.errors.full_messages.to_sentence)
    end
    ticked
  end

  def destroy
    authorize @grocery_list_item, :uncheck?
    @grocery_list_item.edited_by(current_profile).uncheck!
    ticked
  end

  private

  def ticked
    GroceryLists::Broadcaster.changed(@grocery_list_item.grocery_list)
    render turbo_stream: grocery_list_region_streams(reload_grocery_list(@grocery_list_item.grocery_list))
  end
end
