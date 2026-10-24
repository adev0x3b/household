# frozen_string_literal: true

require "test_helper"

class Books::OpenLibraryTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  DATA = {
    "ISBN:9780441013593" => {
      "title" => " Dune ", "authors" => [ { "name" => "Frank Herbert" }, { "name" => "" } ],
      "subjects" => (1..7).map { |n| { "name" => "Subject #{n}" } },
      "cover" => { "small" => "https://covers.openlibrary.org/b/id/14856017-S.jpg", "medium" => "https://covers.openlibrary.org/b/id/14856017-M.jpg" }
    }
  }.freeze

  test "found: the title, the authors, five subjects as genres, the cover's id — with our User-Agent" do
    seen = nil
    result = swapping(Books::OpenLibrary, :perform, ->(request) { seen = request; Response.new("200", DATA.to_json) }) { Books::OpenLibrary.lookup("9780441013593") }

    assert_match(/Household/, seen["User-Agent"])
    assert_includes seen.uri.to_s, "bibkeys=ISBN:9780441013593"

    assert_predicate result, :found?
    assert_equal({ title: "Dune", author: "Frank Herbert", genre_list: "Subject 1, Subject 2, Subject 3, Subject 4, Subject 5", cover_id: 14856017 },
                 result.attributes)
  end

  test "a book with no cover or subjects still fills what it has" do
    body = { "ISBN:9780441013593" => { "title" => "Dune", "authors" => [ { "name" => "Frank Herbert" } ] } }.to_json
    result = swapping(Books::OpenLibrary, :perform, ->(_request) { Response.new("200", body) }) { Books::OpenLibrary.lookup("9780441013593") }

    assert_equal({ title: "Dune", author: "Frank Herbert" }, result.attributes)
  end

  test "an ISBN Open Library doesn't know is not found; a bad answer or no answer is unavailable" do
    none = swapping(Books::OpenLibrary, :perform, ->(_request) { Response.new("200", "{}") }) { Books::OpenLibrary.lookup("9780441013593") }
    assert_equal :not_found, none.reason
    assert_not none.found?

    down = nil
    report = assert_error_reported(Books::OpenLibrary::Error) do
      down = swapping(Books::OpenLibrary, :perform, ->(_request) { Response.new("503", "nope") }) { Books::OpenLibrary.lookup("9780441013593") }
    end
    assert_equal :unavailable, down.reason
    assert_equal "Open Library answered 503", report.error.message
    assert_equal :warning, report.severity

    garbled = swapping(Books::OpenLibrary, :perform, ->(_request) { Response.new("200", "<html>") }) { Books::OpenLibrary.lookup("9780441013593") }
    assert_equal :unavailable, garbled.reason

    gone = swapping(Books::OpenLibrary, :perform, ->(_request) { raise Books::OpenLibrary::Error, "isn't answering (OpenTimeout)" }) { Books::OpenLibrary.lookup("9780441013593") }
    assert_equal :unavailable, gone.reason
  end
end
