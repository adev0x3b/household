# frozen_string_literal: true

require "test_helper"

# Every index page has the navbar search (Components::IndexSearch); a search
# answers with the results frame only, never the input being typed into.
class IndexSearchTest < ActionDispatch::IntegrationTest
  setup do
    @profile = profiles(:alice)
    sign_in @profile
  end

  test "recipes" do
    Recipe.create!(profile: @profile, name: "Lemon cake")
    assert_index_search recipes_path, Views::Recipes::List, query: "sunday", found: "Sunday Roast Chicken", missing: "Lemon cake"
  end

  test "ingredients" do
    assert_index_search ingredients_path, Views::Ingredients::List, query: "flo", found: "Flour", missing: "Eggs"
  end

  test "collections (Healthcare's therapies)" do
    Collection.create!(profile: @profile, name: "Physiotherapy", section: "healthcare")
    assert_index_search collections_path(section: "healthcare"), Views::Collections::List, query: "b12", found: "B12", missing: "Physiotherapy"
  end

  test "grocery lists" do
    GroceryList.create!(profile: @profile, name: "Barbecue")
    assert_index_search grocery_lists_path, Views::GroceryLists::List, query: "weekly", found: "Weekly shop", missing: "Barbecue"
  end

  test "supplies" do
    Supply.create!(profile: @profile, name: "Gauze pads", unit_label: "pcs")
    Supply.create!(profile: @profile, name: "Saline", unit_label: "ml")
    assert_index_search supplies_path, Views::Supplies::List, query: "gauze", found: "Gauze pads", missing: "Saline"
  end

  test "analytes" do
    assert_index_search analytes_path, Views::Analytes::List, query: "gluc", found: "Glucose", missing: "Cholesterol"
  end

  test "books" do
    assert_index_search books_path, Views::Books::List, query: "le guin", found: "The Left Hand of Darkness", missing: "Dune", actions: 2
  end

  test "files" do
    assert_index_search uploads_path, Views::Uploads::List, query: "lease", found: "Lease 2026.pdf", missing: "backup.tar.gz"
  end

  test "conversations" do
    assistant_chat(@profile).update!(title: "Blood test results")
    assistant_chat(@profile).update!(title: "Weekly groceries")
    assert_index_search assistant_chats_path, Views::Assistant::Chats::List, query: "blood", found: "Blood test results", missing: "Weekly groceries"
  end

  test "a search with no results says so" do
    get recipes_path(q: "nothing like this"), headers: { "Turbo-Frame" => Views::Recipes::List::FRAME_ID }

    assert_includes response.body, "No recipes match your search."
  end

  test "show pages put their edit button in the navbar" do
    get recipe_path(recipes(:roast_chicken))
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", edit_recipe_path(recipes(:roast_chicken))

    get grocery_list_path(grocery_lists(:weekly_shop))
    assert_select ".navbar-topbar-controls .item-menu a.item-menu__entry[href=?]",
                  edit_grocery_list_path(grocery_lists(:weekly_shop)) # behind finish and share

    get collection_path(collections(:b12))
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", edit_collection_path(collections(:b12))
  end

  test "a conversation's buttons are in the navbar, and the way back to the list in its header" do
    chat = assistant_chat(@profile)

    get assistant_chat_path(chat)

    assert_select ".navbar-topbar-controls a.page-controls__action[href=?][data-turbo-method=post]", assistant_chats_path
    assert_select ".assistant__header a.page-header__back[href=?]", assistant_chats_path
    assert_select ".assistant__header .page-controls__action", false
  end

  private

  def assert_index_search(path, results, query:, found:, missing:, actions: 1)
    frame_id = results::FRAME_ID

    get path
    assert_response :success
    assert_select ".navbar-topbar-controls form[data-turbo-frame=?] input[type=search][name=q]", frame_id
    assert_select ".navbar-topbar-controls .page-controls__action[aria-label]", actions # its "new" button, and "more" where a page has others
    assert_select ".app-content .page-controls__action", false
    assert_select "turbo-frame##{frame_id}"

    get path, params: { q: query }, headers: { "Turbo-Frame" => frame_id }
    assert_response :success
    assert_select "turbo-frame##{frame_id}"
    assert_select "input[type=search]", false, "a search response must not re-render the search input"
    assert_includes response.body, found
    assert_not_includes response.body, missing
  end
end
