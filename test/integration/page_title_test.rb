# frozen_string_literal: true

require "test_helper"

# A page is named in two places that say the same thing: the browser tab
# (Views::Base#page_title) and its own h1 (Components::PageHeader). The top
# bar keeps the wordmark on every page.
class PageTitleTest < ActionDispatch::IntegrationTest
  setup { sign_in profiles(:bob) }

  test "Home is named in its header and its tab, and the top bar keeps the wordmark" do
    get root_path

    assert_select "title", "Home · Household"
    assert_select ".navbar-topbar a.navbar-logo-link[href='#{root_path}'] .navbar-logo-text", text: "Household"
    assert_select ".page-header h1.page-title", "Home"
  end

  test "an index page is named after itself, once on the page and in the tab, and one folded under a section leads back to it" do
    get books_path

    assert_select "title", "Bookshelf · Household"
    assert_select "h1.page-title", 1
    assert_select ".page-header h1.page-title", "Bookshelf"
    assert_select ".page-header__back", 0
    assert_select ".navbar-topbar a.navbar-logo-link"

    get supplies_path

    assert_select "title", "Supplies · Household"
    assert_select ".page-header a.page-header__back[href=?][aria-label=Healthcare]", home_section_path(section: "healthcare")
  end

  test "a record's page is named after the record and leads back to its list" do
    recipe = recipes(:roast_chicken)
    sign_in recipe.profile

    get recipe_path(recipe)

    assert_select "title", "#{recipe.name} · Household"
    assert_select ".page-header h1.page-title", recipe.name
    assert_select ".page-header a.page-header__back[href=?][aria-label='Back to recipes']", recipes_path
  end
end
