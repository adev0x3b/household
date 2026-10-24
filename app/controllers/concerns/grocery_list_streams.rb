# frozen_string_literal: true

# The turbo streams a change to a grocery list's items answers with: the
# list page's live regions, its header and its items, redrawn in place while
# the list is being shopped.
module GroceryListStreams
  private

  def grocery_list_region_streams(grocery_list)
    [
      turbo_stream.replace(Views::GroceryLists::Header.dom_id(grocery_list),
                           Views::GroceryLists::Header.new(grocery_list: grocery_list, viewer: current_profile)),
      turbo_stream.replace(Views::GroceryLists::Items.dom_id(grocery_list), Views::GroceryLists::Items.new(grocery_list: grocery_list))
    ]
  end

  # Fresh, with everything the regions render: a bare `reload` would drop
  # the includes and load every row's ingredient one by one.
  def reload_grocery_list(grocery_list) = GroceryList.with_everything.find(grocery_list.id)
end
