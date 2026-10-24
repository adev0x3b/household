# frozen_string_literal: true

# A grocery list's completion: put there when the shopping is done, taken
# away to shop the list again. Everyone looking at the list hears of it
# (GroceryLists::Broadcaster).
class GroceryListCompletionsController < ApplicationController
  before_action { @grocery_list = policy_scope(GroceryList).with_everything.find(params[:grocery_list_id]) }

  def create
    authorize @grocery_list, :finish?
    @grocery_list.finish!
    changed(:finished)
  end

  def destroy
    authorize @grocery_list, :reopen?
    @grocery_list.reopen!
    changed(:reopened)
  end

  private

  def changed(notice)
    GroceryLists::Broadcaster.changed(@grocery_list)
    redirect_back_after_save(grocery_list_path(@grocery_list), notice: t("grocery_lists.notices.#{notice}"))
  end
end
