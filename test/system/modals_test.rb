# frozen_string_literal: true

require "application_system_test_case"

# A modal by keyboard alone: it takes the focus when it opens, keeps it
# from the page behind, closes on Escape, and gives the focus back to what
# opened it.
class ModalsTest < ApplicationSystemTestCase
  setup do
    sign_in profiles(:alice)
    visit books_path
  end

  test "a modal opened by keyboard starts at the field its form names and keeps the focus inside" do
    open_new_book

    assert_focused find_field("book[title]")
    20.times do
      press(:tab)
      assert_focus_kept_from_the_page
    end
  end

  test "Escape closes the modal from a text field and gives the focus back to what opened it" do
    add = open_new_book
    fill_in "book[title]", with: "Dune"

    press(:escape)

    assert_no_selector ".modal"
    assert_focused add
  end

  test "a modal closed by its button gives the focus back too" do
    add = open_new_book

    press_tab_until find_button(I18n.t("modal.cancel"))
    press(:enter)

    assert_no_selector ".modal"
    assert_focused add
  end

  # The entry that opened it is folded away with its menu by then, so the
  # focus goes back to the menu's button.
  test "a modal opened from an item's menu gives the focus back to the menu's button" do
    more = within("#book_#{books(:dune).id}") { find_button(I18n.t("books.card.more")) }
    press_tab_until more
    press :enter
    press_tab_until find_link(I18n.t("books.card.edit"))
    press :enter
    assert_selector ".modal[open]", text: I18n.t("books.form.edit_title")

    press :escape

    assert_no_selector ".modal"
    assert_focused more
  end

  test "a toast that shows while the modal is open shows inside it, where it can be pressed" do
    open_new_book
    page.execute_script(<<~JS)
      document.getElementById("toast-container").insertAdjacentHTML("beforeend",
        '<div class="toast toast--notice" data-controller="toast"><span class="toast__message">Noted</span></div>')
    JS

    within(".modal") { assert_selector ".toast", text: "Noted" }
  end

  private

  # The page's "Add a book", reached and pressed from the keyboard.
  def open_new_book
    add = find_link(I18n.t("books.index.new"))
    press_tab_until add
    press(:enter)
    assert_selector ".modal[open]", text: I18n.t("books.form.new_title")
    add
  end

  # Past the dialog's last control the browser moves the focus to its own
  # controls before coming back to the first, which a page sees as no
  # element having it; the page behind is never reached.
  def assert_focus_kept_from_the_page
    on_the_page = page.evaluate_script(<<~JS)
      document.activeElement !== document.body && !document.querySelector(".modal").contains(document.activeElement)
    JS
    assert_not on_the_page, "the focus reached #{page.active_element.tag_name} behind the modal"
  end
end
