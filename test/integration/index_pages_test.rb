# frozen_string_literal: true

require "test_helper"

# A list that only grows is shown a page at a time, with links to the rest:
# nothing is cut off without saying so.
class IndexPagesTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
  end

  test "an index shows a page of cards and the links to the next" do
    Recipe.insert_all(Array.new(SearchableIndex::PAGE_SIZE) { |i| { profile_id: @alice.id, name: "Zucchini dish #{i.to_s.rjust(2, "0")}" } })
    shown = policy_count(Recipe)

    get recipes_path
    assert_select ".recipe-card__name", SearchableIndex::PAGE_SIZE
    assert_select "nav.pagination a.pagination__link[href=?][data-turbo-frame=?]", recipes_path(page: 2), Views::Recipes::List::FRAME_ID

    get recipes_path(page: 2), headers: { "Turbo-Frame" => Views::Recipes::List::FRAME_ID }
    assert_select ".recipe-card__name", shown - SearchableIndex::PAGE_SIZE
    assert_select ".recipe-card__name", text: "Zucchini dish 23"
  end

  test "the shelf keeps its filters from one page to the next" do
    Book.insert_all(Array.new(Books::IndexQuery::PER_PAGE + 1) { |i| { profile_id: @alice.id, title: "Volume #{i}", author: "Anon", status: Book.statuses[:read] } })

    get books_path(status: "read")
    assert_select ".book-card__title", Books::IndexQuery::PER_PAGE
    assert_select "nav.pagination a[href=?]", books_path(page: 2, status: "read")
  end

  test "the finished grocery lists come a page at a time, under their own page links" do
    GroceryList.insert_all(Array.new(SearchableIndex::PAGE_SIZE + 1) { |i| { profile_id: @alice.id, name: "Old shop #{i}", status: GroceryList.statuses[:completed] } })
    finished = policy_count(GroceryList.completed)

    get grocery_lists_path
    assert_select "details#grocery_lists_completed:not([open]) .grocery-list-card__name", SearchableIndex::PAGE_SIZE
    assert_select "details#grocery_lists_completed summary", text: /#{finished}/
    assert_select "nav.pagination a[href=?]", grocery_lists_path(finished_page: 2)

    get grocery_lists_path(finished_page: 2)
    assert_select "details#grocery_lists_completed[open] .grocery-list-card__name", finished - SearchableIndex::PAGE_SIZE
    assert_select "#grocery_lists_list #grocery_list_#{grocery_lists(:weekly_shop).id}"
  end

  test "the assistant's chats are paged rather than cut off" do
    Assistant::Chat.insert_all(Array.new(SearchableIndex::PAGE_SIZE + 1) { |i| { profile_id: @alice.id, title: "Chat #{i}", ruby_llm_model_id: ruby_llm_models(:qwen3).id } })

    get assistant_chats_path
    assert_select ".assistant__chat", SearchableIndex::PAGE_SIZE
    assert_select "nav.pagination a[href=?]", assistant_chats_path(page: 2)
  end

  test "a file's trail says how many older entries it doesn't list" do
    upload = keep_file(@alice)
    UploadActivity.insert_all(Array.new(Uploads::Page::ACTIVITY + 2) { { upload_id: upload.id, profile_id: @alice.id, action: UploadActivity.actions[:downloaded] } })
    older = upload.upload_activities.count - Uploads::Page::ACTIVITY

    get upload_path(upload)
    assert_select ".upload-activity__entry", Uploads::Page::ACTIVITY
    assert_select ".upload-activity__older", text: I18n.t("uploads.activity.older", count: older)
  end

  test "the admin's households are paged" do
    @alice.update!(role: :admin)
    Household.insert_all(Array.new(Admin::HouseholdsController::PER_PAGE) { |i| { name: "Casa #{i}", slug: "casa-#{i}" } })

    get admin_households_path
    assert_select ".household__row", Admin::HouseholdsController::PER_PAGE
    assert_select "nav.pagination a[href=?]", admin_households_path(page: 2)
  end

  private

  def policy_count(scope) = Pundit.policy_scope!(@alice, scope).count
end
