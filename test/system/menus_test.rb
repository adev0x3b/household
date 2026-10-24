# frozen_string_literal: true

require "application_system_test_case"

# A menu behind a button, by keyboard alone: its entries come next in the
# Tab order, it folds when the focus leaves it, and Escape gives the focus
# back to its button.
class MenusTest < ApplicationSystemTestCase
  setup do
    sign_in profiles(:alice)
    visit books_path
  end

  test "an item's menu is entered with Tab and folds once Tab leaves its last entry" do
    more = open_more_of(books(:dune))

    press(:tab)
    assert_focus_within ".item-menu__menu.is-open"
    press_tab_until find(".item-menu__menu.is-open .item-menu__entry:last-child")
    press(:tab)

    assert_no_selector ".item-menu__menu.is-open"
    assert_equal "false", more["aria-expanded"]
  end

  test "Escape from an entry folds the menu and gives the focus back to its button" do
    more = open_more_of(books(:dune))
    press(:tab)

    press(:escape)

    assert_no_selector ".item-menu__menu.is-open"
    assert_focused more
  end

  test "the account menu folds when Shift+Tab leaves it by its button" do
    account = find_button(I18n.t("navbar.account.label"))
    press_tab_until account
    press(:enter)
    assert_selector ".account-menu__panel.is-open"

    press_shift_tab

    assert_no_selector ".account-menu__panel.is-open"
  end

  private

  def open_more_of(book)
    more = within("#book_#{book.id}") { find_button(I18n.t("books.card.more")) }
    press_tab_until more
    press(:enter)
    assert_selector ".item-menu__menu.is-open"
    more
  end
end
