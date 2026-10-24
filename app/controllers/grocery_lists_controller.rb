# frozen_string_literal: true

# The grocery lists: the index, a list's page as it is shopped, and the
# modal to name one. Finishing one is GroceryListCompletionsController's,
# the items GroceryListItemsController's.
class GroceryListsController < ApplicationController
  include SearchableIndex
  include KeepsWhatWasTyped

  before_action :set_grocery_list, only: [ :show, :edit, :update, :destroy ]

  def index
    lists = policy_scope(GroceryList).search(search_query).for_cards
    shopping = lists.active.order(:name, :id)
    finished = index_page(lists.completed.newest_first, param: Views::GroceryLists::List::FINISHED_PAGE)

    render_searchable_index(
      page: Views::GroceryLists::Index.new(shopping: shopping, finished: finished, viewer: current_profile, query: search_query),
      results: Views::GroceryLists::List.new(shopping: shopping, finished: finished, viewer: current_profile, query: search_query)
    )
  end

  def show
    authorize @grocery_list

    render_page Views::GroceryLists::Show.new(grocery_list: @grocery_list, viewer: current_profile)
  end

  def new
    @grocery_list = GroceryList.new
    authorize @grocery_list

    render_modal(form_view(@grocery_list, grocery_lists_path), page: grocery_lists_path)
  end

  def edit
    authorize @grocery_list

    render_modal(form_view(@grocery_list, grocery_list_path(@grocery_list)), page: @grocery_list)
  end

  def create
    @grocery_list = GroceryList.new(grocery_list_params.merge(profile: current_profile))
    authorize @grocery_list

    if @grocery_list.save
      redirect_back_after_save(grocery_list_path(@grocery_list), notice: t("grocery_lists.notices.created"))
    else
      render turbo_stream: redraw_modal(form_view(@grocery_list, grocery_lists_path)), status: :unprocessable_content
    end
  end

  def update
    authorize @grocery_list

    if @grocery_list.edit_as(current_profile, typed: typed_fields(@grocery_list, grocery_list_params)) { @grocery_list.update(grocery_list_params) }
      GroceryLists::Broadcaster.changed(@grocery_list)
      redirect_back_after_save(grocery_list_path(@grocery_list), notice: t("grocery_lists.notices.updated"))
    else
      render turbo_stream: redraw_modal(form_view(@grocery_list, grocery_list_path(@grocery_list))), status: :unprocessable_content
    end
  end

  def destroy
    authorize @grocery_list

    viewers = @grocery_list.people_with_access
    @grocery_list.destroy!
    GroceryLists::Broadcaster.destroyed(@grocery_list, viewers)

    redirect_after_destroy(grocery_list_path(@grocery_list), list: grocery_lists_path, notice: t("grocery_lists.notices.destroyed"))
  end

  private

  def set_grocery_list
    @grocery_list = policy_scope(GroceryList).with_everything.find(params[:id])
  end

  def grocery_list_params
    params.expect(grocery_list: %i[name lock_version])
  end

  def form_view(grocery_list, url)
    Views::GroceryLists::Modals::Form.new(grocery_list: grocery_list, url: url)
  end
end
