# frozen_string_literal: true

require "test_helper"

class Books::GoogleBooksTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  LINKS = %(x({"ISBN:9788807091971":{"bib_key":"ISBN:9788807091971","info_url":"https://books.google.com/books?id=J-SZ0QEACAAJ\\u0026source=gbs_ViewAPI","thumbnail_url":"https://books.google.com/books/content?id=J-SZ0QEACAAJ\\u0026printsec=frontcover\\u0026img=1\\u0026zoom=5"}});)
  VOLUME = {
    "volumeInfo" => {
      "title" => "Il riso della Medusa", "subtitle" => " Manifesto femminista ", "authors" => [ "Hélène Cixous" ],
      "categories" => [ "Literary Criticism / General", "Social Science / Feminism & Feminist Theory", "literary criticism" ],
      "imageLinks" => { "smallThumbnail" => "http://books.google.com/books/content?id=J-SZ0QEACAAJ&zoom=5&imgtk=X", "thumbnail" => "http://books.google.com/books/content?id=J-SZ0QEACAAJ&zoom=1&imgtk=X" }
    }
  }.freeze

  isolate_env "GOOGLE_BOOKS_API_KEY"
  setup { ENV["GOOGLE_BOOKS_API_KEY"] = "test-key" }

  # The keyless Dynamic Links answer, then the keyed volume: told apart by host.
  def answering(links: LINKS, volume: VOLUME.to_json, volume_code: "200", &block)
    seen = []
    result = swapping(Books::GoogleBooks, :perform, ->(request) {
      seen << request.uri
      request.uri.host == "books.google.com" ? Response.new("200", links) : Response.new(volume_code, volume)
    }, &block)
    [ result, seen ]
  end

  test "found: the ISBN resolved to a volume keylessly, then its title with subtitle, authors, categories as genres and a cover from the volume id" do
    result, seen = answering { Books::GoogleBooks.lookup("9788807091971") }

    assert_equal [ "books.google.com", "www.googleapis.com" ], seen.map(&:host)
    assert_includes seen.first.query, "bibkeys=ISBN%3A9788807091971"
    assert_not_includes seen.first.query, "key="
    assert_equal "/books/v1/volumes/J-SZ0QEACAAJ", seen.last.path
    assert_includes seen.last.query, "key=test-key"
    assert_predicate result, :found?
    assert_equal({ title: "Il riso della Medusa: Manifesto femminista", author: "Hélène Cixous",
                   genres: [ "Literary Criticism", "Social Science", "Feminism & Feminist Theory" ],
                   cover_url: "https://books.google.com/books/content?id=J-SZ0QEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api" }, result.attributes)
  end

  test "no cover, no cover_url; an unknown ISBN is not found before the key is used" do
    bare = VOLUME.deep_dup.tap { |v| v["volumeInfo"].delete("imageLinks") }.to_json
    result, = answering(volume: bare) { Books::GoogleBooks.lookup("9788807091971") }
    assert_nil result.attributes[:cover_url]
    assert_equal "Il riso della Medusa: Manifesto femminista", result.attributes[:title]

    result, seen = answering(links: "x({});") { Books::GoogleBooks.lookup("9780306406158") }
    assert_equal :not_found, result.reason
    assert_equal [ "books.google.com" ], seen.map(&:host)
  end

  test "a bad answer is unavailable and says it was Google; no key means it isn't asked" do
    result = nil
    report = assert_error_reported(Books::GoogleBooks::Error) do
      result, = answering(volume_code: "503", volume: "{}") { Books::GoogleBooks.lookup("9788807091971") }
    end
    assert_equal :unavailable, result.reason
    assert_equal "Google Books answered 503", report.error.message
    assert_equal :warning, report.severity

    garbled, = answering(links: "<html>") { Books::GoogleBooks.lookup("9788807091971") }
    assert_equal :unavailable, garbled.reason

    ENV.delete("GOOGLE_BOOKS_API_KEY")
    assert_not Books::GoogleBooks.configured?
    silent = swapping(Books::GoogleBooks, :perform, ->(_request) { flunk "no request without a key" }) { Books::GoogleBooks.lookup("9788807091971") }
    assert_equal :unavailable, silent.reason
  end
end
