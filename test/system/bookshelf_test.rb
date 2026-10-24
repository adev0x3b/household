# frozen_string_literal: true

require "application_system_test_case"

# A book's page in the browser: its cover, and the live updates it listens to.
class BookshelfTest < ApplicationSystemTestCase
  # A cover is hot-linked from wherever the book was found, so it can fail to
  # load; the shelf then shows the book's stand-in (book_cover_controller.js).
  test "a cover that fails to load gives way to the book's title" do
    # A cover that can't load, without reaching Google from the test.
    books(:dune).update_columns(cover_id: nil, cover_url: "/covers/missing.jpg")
    sign_in profiles(:alice)
    visit book_path(books(:dune))

    within(".book-show__cover") do
      assert_no_selector "img"
      assert_selector ".book-cover__placeholder", text: "Dune"
    end
  end

  # Every reader of the book is pushed a refresh when it changes, the writer
  # too, and Turbo leaves the writer's own out. The page that answers the
  # next press still brings its toast (catch_up_controller.js).
  test "each change to a book's status is confirmed, though the page hears of it live" do
    sign_in profiles(:alice)
    visit book_path(books(:dune))
    assert_listening

    click_on I18n.t("books.status.reading")
    assert_text I18n.t("books.notices.status.reading")

    click_on I18n.t("books.status.read")
    assert_text I18n.t("books.notices.status.read")
    assert_predicate books(:dune).reload, :read?
  end
end
