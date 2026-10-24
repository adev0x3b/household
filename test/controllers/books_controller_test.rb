# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class BooksControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @alice = profiles(:alice)
    @reading = books(:left_hand)
    @read = books(:dune)
    @bobs = books(:hail_mary) # shared with alice
    sign_in @alice
  end

  test "the shelf shows covers, status pills with counts, genre chips and the navbar's buttons" do
    get books_path

    assert_response :success
    assert_select "turbo-frame#books_results #books_grid #book_#{@reading.id}"
    assert_select "#book_#{@read.id} img.book-cover__image[src=?]", "https://covers.openlibrary.org/b/id/12345-M.jpg"
    assert_select "#book_#{@reading.id} .book-cover__placeholder"
    assert_select "#book_#{@bobs.id}", count: 0 # one's own shelf by default
    assert_select ".segmented-filter__option[aria-current=true]", text: /All.*2/
    assert_select ".segmented-filter__option", text: /Reading.*1/
    assert_select ".genre-chip", text: /Science fiction.*2/
    # A filter revisits the page as a page refresh (morphed, scroll kept), never a plain visit.
    assert_select ".segmented-filter__option[data-turbo-action=replace][href=?]", books_path(status: "reading")
    assert_select ".genre-chip[data-turbo-action=replace][href=?]", books_path(genre: "Science fiction")
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", new_book_path
    assert_select ".navbar-topbar-controls .item-menu a.item-menu__entry[href=?]", scanner_books_path
    assert_select ".navbar-topbar-controls .item-menu a.item-menu__entry[href=?]", new_bookshelf_share_path
    assert_select "a.navbar-link.is-current[href='#{books_path}']"
    assert_select "#book_#{@reading.id} a.item-action[data-turbo-method=patch][href=?]", book_status_path(@reading, status: "read")
    assert_select "#book_#{@reading.id} .item-menu a.item-menu__entry[href=?]", book_status_path(@reading, status: "dropped")
    assert_select "#book_#{@reading.id} .item-menu a.item-menu__entry--danger[href=?][data-turbo-method=delete]", book_path(@reading)
    assert_select "#book_#{@reading.id} .item-menu__button[aria-expanded=false][aria-label=More]"
    assert_select "#book_#{@reading.id} .card__actions > .item-action", 1 # one step visible, the rest in the menu
    assert_select "#book_#{@read.id} a.item-action[href=?]", book_status_path(@read, status: "reading")
    assert_select "#book_#{@read.id} .book-card__rating .is-sr-only", text: "Rated 5 of 5"

    @read.update!(volume: 2)
    get books_path
    assert_select "#book_#{@read.id} .book-card__title", text: "Dune, vol. 2"
  end

  test "a cover refused by a field the form doesn't show is still said" do
    patch book_path(@read), params: { book: { cover_url: "https://example.com/cover.jpg" } }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_form_error "Cover is invalid"
  end

  test "status, genre, sort and whose-shelf filters, kept by the navbar search" do
    get books_path(status: "read")
    assert_select "#book_#{@read.id}"
    assert_select "#book_#{@reading.id}", count: 0
    assert_select ".navbar-topbar-controls form input[type=hidden][name=status][value=read]"

    get books_path(status: "read", q: "dune")
    assert_select ".navbar-topbar-controls form input[type=hidden][name=status][value=read]"
    assert_select ".navbar-topbar-controls form input[name=q]", count: 1 # the search field alone carries the words

    get books_path(status: "dropped")
    assert_select "#books_empty", text: "Nothing dropped."

    get books_path(genre: "Classics")
    assert_select "#book_#{@reading.id}"
    assert_select "#book_#{@read.id}", count: 0
    assert_select ".genre-chip.is-current[aria-current=true]", text: /Classics/

    get books_path(sort: "title")
    assert_select "#books_grid .card:first-child", id: "book_#{@read.id}"
    assert_select "select[name=sort] option[selected][value=title]"

    get books_path(shelf: "everyone")
    assert_select "#book_#{@bobs.id} .share-whose", text: /Bob/
    assert_select "#book_#{@reading.id}"

    get books_path(shelf: profiles(:bob).id)
    assert_select "#book_#{@bobs.id}"
    assert_select "#book_#{@reading.id}", count: 0
    assert_select "select[name=shelf] option[selected][value=?]", profiles(:bob).id.to_s

    get books_path(q: "dune", status: "read"), headers: { "Turbo-Frame" => Views::Books::List::FRAME_ID }
    assert_response :success
    assert_includes response.body, "Dune"
    assert_select "input[type=search]", false
  end

  test "without anything shared there is no shelf picker, and an empty shelf says so" do
    sign_in profiles(:carol)

    get books_path
    assert_select "select[name=shelf]", count: 0
    assert_select "#books_empty", text: /No books yet/
  end

  test "a book's page: the owner's status pills and navbar buttons; a housemate sees a badge and no buttons" do
    get book_path(@reading)
    assert_response :success
    assert_select ".book-show .segmented-filter__option[aria-current=true]", text: /Reading/
    assert_select ".segmented-filter__option[data-turbo-method=patch][href=?]", book_status_path(@reading, status: "read")
    assert_select ".segmented-filter__option[data-turbo-action]", count: 0, message: "an action, not a filter: no page refresh"
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", edit_book_path(@reading)
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", new_book_share_path(book_id: @reading.id)
    assert_select ".navbar-topbar-controls a.item-menu__entry--danger[data-turbo-method=delete][href=?]", book_path(@reading)
    assert_select ".book-show__facts .genre-chip[href=?]", books_path(genre: "Classics")
    assert_select ".book-show__attribution a[href=?]", "https://openlibrary.org/isbn/9780441478125"

    @reading.update!(cover_id: nil, cover_url: "https://books.google.com/books/content?id=x")
    get book_path(@reading)
    assert_select "img.book-cover__image[src='https://books.google.com/books/content?id=x&fife=w400']"
    assert_select ".book-show__attribution", text: "Cover from Google Books"
    assert_select ".book-show__attribution a", count: 0

    get book_path(@bobs)
    assert_response :success
    assert_select ".segmented-filter", count: 0
    assert_select ".status-badge", text: /Wants to read/
    assert_select ".book-show__shared", text: /Bob's book/
    assert_select ".navbar-topbar-controls .page-controls__action", count: 0

    sign_in profiles(:carol)
    get book_path(@reading)
    assert_not_equal 200, response.status
  end

  test "add: the modal with the genres known, then back to the shelf as it was" do
    get new_book_path, as: :turbo_stream

    assert_response :success
    assert_select "form.modal__form input[name='book[isbn]']"
    assert_select "form.modal__form[method=post] button[formaction=?][formnovalidate][data-turbo-stream]:not([formmethod])", lookup_books_path
    assert_select "datalist#book_genres option[value='Science fiction']"

    shelf = books_path(status: "want_to_read")
    assert_difference -> { @alice.books.count }, 1 do
      post books_path, params: { book: { title: "Circe", author: "Madeline Miller", genre_list: "Fantasy, Mythology", isbn: "0316556343" } },
                       headers: submitted_from(shelf)
    end
    assert_redirected_to shelf
    circe = @alice.books.find_by!(title: "Circe")
    assert_equal [ "9780316556347", [ "Fantasy", "Mythology" ], "want_to_read" ], [ circe.isbn, circe.genres, circe.status ]
    follow_redirect!
    assert_toast "Book added"
    assert_select "#book_#{circe.id}"
    assert_select "#book_#{@read.id}", count: 0 # the shelf kept its filter

    post books_path, params: { book: { title: "Bad", author: "A", isbn: "123" } }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_form_error "isn't a valid ISBN"
  end

  test "a change made on the book's page comes back to it, title and all" do
    get edit_book_path(@read), as: :turbo_stream
    assert_response :success
    assert_select "form.modal__form[action=?]", book_path(@read)
    assert_select "form.modal__form input[name=_method][value=patch]"
    assert_select "button[formaction=?]:not([formmethod])", lookup_book_path(@read)
    assert_select "select[name='book[rating]'] option[selected][value='5']"

    patch book_path(@read), params: { book: { title: "Dune Messiah", rating: 4, notes: "Spice." } }, headers: submitted_from(book_path(@read))
    assert_redirected_to book_path(@read)
    assert_equal [ "Dune Messiah", 4, "Spice." ], [ @read.reload.title, @read.rating, @read.notes ]
    follow_redirect!
    assert_select "title", text: /Dune Messiah/
    assert_select ".page-header h1.page-title", text: "Dune Messiah"
  end

  test "a book with an Open Library cover saves from its form sent back as it came" do
    get edit_book_path(@read), as: :turbo_stream
    sent = book_fields(Nokogiri::HTML5.fragment(response.body).at_css("form.modal__form"))
    assert_equal "", sent["cover_url"]

    patch book_path(@read), params: { book: sent.merge("notes" => "Spice.") }, headers: submitted_from(book_path(@read))
    assert_redirected_to book_path(@read)
    assert_equal [ "Spice.", 12345 ], [ @read.reload.notes, @read.cover_id ]
    assert_predicate @read[:cover_url], :blank?
  end

  test "delete from the shelf comes back to it as it was; from the book's page it goes to the shelf; never someone else's" do
    shelf = books_path(status: "read")
    delete book_path(@read), headers: submitted_from(shelf)
    assert_redirected_to shelf
    assert_not Book.exists?(@read.id)
    follow_redirect!
    assert_toast "Book deleted."

    delete book_path(@reading), headers: submitted_from(book_path(@reading))
    assert_redirected_to books_path
    assert_not Book.exists?(@reading.id)

    delete book_path(@bobs), as: :turbo_stream
    assert Book.exists?(@bobs.id)
  end

  test "a change reaches the shelf and book pages of everyone who sees the book, the deletion included" do
    bob, carol = profiles(:bob), profiles(:carol)
    @alice.bookshelf!.bookshelf_shares.create!(profile: bob)
    @reading.book_shares.create!(profile: carol)

    get book_path(@reading)
    assert_select "turbo-cable-stream-source[signed-stream-name=?]", Turbo::StreamsChannel.signed_stream_name([ @alice, :books ])

    patch book_status_path(@reading, status: "read")
    delete book_path(@reading)
    post books_path, params: { book: { title: "Circe", author: "Madeline Miller" } }

    assert_turbo_stream_broadcasts [ @alice, :books ], count: 3
    assert_turbo_stream_broadcasts [ bob, :books ], count: 3
    assert_turbo_stream_broadcasts [ carol, :books ], count: 2 # a new book on the shelf is not one shared with her
    assert_no_turbo_stream_broadcasts [ profiles(:outsider), :books ]
    assert_equal [ "refresh" ], capture_turbo_stream_broadcasts([ bob, :books ]).map { _1["action"] }.uniq
  end

  test "the scanner modal has the camera, the photo fallback, the typed ISBN and our own wasm" do
    get scanner_books_path, as: :turbo_stream

    assert_response :success
    assert_select "[data-controller=barcode-scanner][data-barcode-scanner-wasm-url-value$='.wasm']"
    assert_select "video[data-barcode-scanner-target=video]"
    assert_select "input[type=file][accept='image/*'][capture=environment]"
    assert_select "form[action=?][method=post][data-turbo-stream] input[name=isbn][data-barcode-scanner-target=isbn]", lookup_books_path
    assert_select "form[data-controller=barcode-scanner] .modal__footer button[type=submit]", I18n.t("books.scan.look_up")
  end

  test "lookup fills the form from Open Library, says when it can't, and refuses what isn't an ISBN" do
    found = Books::Lookup::Result.new(attributes: { title: "Circe", author: "Madeline Miller", genre_list: "Fantasy, Mythology", cover_id: 8283869 }, error: nil, source: :open_library)
    swapping(Books::Lookup, :call, ->(_isbn, **) { found }) do
      post lookup_books_path, params: { isbn: "0316556343" }, as: :turbo_stream
    end
    assert_response :success
    assert_select "input[name='book[isbn]'][value=9780316556347]"
    assert_select "input[name='book[title]'][value=Circe]"
    assert_select "input[name='book[genre_list]'][value='Fantasy, Mythology']"
    assert_select "input[name='book[cover_id]'][value=8283869]"
    assert_select "img.book-cover__image[src*='8283869-M.jpg']"
    assert_select ".notice", text: /Filled in from Open Library/

    # a series: the number read from the title, then proposed from the shelf when the catalogue has none
    numbered = Books::Lookup::Result.new(attributes: { title: "Naruto", volume: 27, author: "Masashi Kishimoto" }, error: nil, source: :google_books)
    swapping(Books::Lookup, :call, ->(_isbn, **) { numbered }) { post lookup_books_path, params: { isbn: "9788828767640" }, as: :turbo_stream }
    assert_select "input[name='book[title]'][value=Naruto]"
    assert_select "input[name='book[volume]'][value=27]"
    assert_select ".help", text: /this volume's number/

    @alice.books.create!(title: "Sugar sugar rune. New edition", author: "Moyoco Anno", volume: 1)
    unnumbered = Books::Lookup::Result.new(attributes: { title: "Sugar sugar rune. New edition", author: "Moyoco Anno" }, error: nil, source: :google_books)
    swapping(Books::Lookup, :call, ->(_isbn, **) { unnumbered }) { post lookup_books_path, params: { isbn: "9788822663863" }, as: :turbo_stream }
    assert_select "input[name='book[volume]'][value=2]"
    assert_select ".help", text: /after vol. 1/

    google = Books::Lookup::Result.new(attributes: { title: "Il nome della rosa", author: "Umberto Eco", genres: [ "Fiction" ], cover_url: "https://books.google.com/books/content?id=x" }, error: nil, source: :google_books)
    swapping(Books::Lookup, :call, ->(_isbn, **) { google }) do
      post lookup_books_path, params: { isbn: "9788845292316" }, as: :turbo_stream
    end
    assert_select ".notice", text: /Filled in from Google Books/
    assert_select "input[name='book[cover_url]'][value='https://books.google.com/books/content?id=x']"
    assert_select "img.book-cover__image[src='https://books.google.com/books/content?id=x']"

    not_found = Books::Lookup::Result.new(attributes: {}, error: :not_found, source: nil)
    swapping(Books::Lookup, :call, ->(_isbn, **) { not_found }) do
      post lookup_books_path, params: { book: { isbn: "978-0-316-55634-7", notes: "typed first" } }, as: :turbo_stream
    end
    assert_select ".notice--action", text: /doesn't know this ISBN/
    assert_select "input[name='book[isbn]'][value=9780316556347]"
    assert_select "textarea[name='book[notes]']", text: "typed first"

    post lookup_books_path, params: { isbn: "12345" }, as: :turbo_stream
    assert_toast "That isn't an ISBN"
    assert_select "form.modal__form", count: 0

    post lookup_books_path, params: { isbn: "9780441013593" }, as: :turbo_stream # Dune, already there
    assert_includes response.body, "is already on your shelf"
    assert_select "form.modal__form", count: 0

    swapping(Books::Lookup, :call, ->(_isbn, **) { found }) do
      patch lookup_book_path(@read), params: { isbn: "9780441013593" }, as: :turbo_stream # editing Dune itself
    end
    assert_select "form.modal__form[action=?]", book_path(@read)
  end

  private

  # What the form sends when it is saved untouched, by field name.
  def book_fields(form)
    form.css("input[name^='book['], select[name^='book['], textarea[name^='book[']").to_h do |field|
      value = case field.name
      when "select" then field.at_css("option[selected]")&.[]("value")
      when "textarea" then field.text
      else field["value"]
      end
      [ field["name"][/\Abook\[(\w+)\]\z/, 1], value.to_s ]
    end
  end
end
