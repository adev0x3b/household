# frozen_string_literal: true

require "test_helper"

class BookStatusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @reading = books(:left_hand)
    @read = books(:dune)
    sign_in @alice
  end

  test "one tap moves a book on and stamps the date; the shelf comes back on the filter it was on" do
    # Every request on one clock: a session idle from the 7th to today would end (Devise's timeout).
    travel_to Time.zone.local(2026, 10, 7, 9)
    shelf = books_path(status: "reading")
    patch book_status_path(@reading, status: "read"), headers: submitted_from(shelf)
    assert_redirected_to shelf
    assert_predicate @reading.reload, :read?
    assert_equal Date.new(2026, 10, 7), @reading.finished_on
    follow_redirect!
    assert_select ".books", text: /Nothing being read right now./
    assert_toast "Finished. Rate it whenever you like."

    patch book_status_path(@read, status: "reading")
    assert_redirected_to book_path(@read)
    assert_predicate @read.reload, :reading?

    patch book_status_path(@reading, status: "nope"), as: :turbo_stream
    assert_response :unprocessable_content
    assert_toast I18n.t("refusals.unknown_choice")

    sign_in profiles(:bob)
    patch book_status_path(@reading, status: "dropped"), as: :turbo_stream
    assert_not @reading.reload.dropped?
  ensure
    travel_back
  end
end
