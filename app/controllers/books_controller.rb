# frozen_string_literal: true

# The bookshelf: a member's books as a cover grid with a status filter,
# genre chips and the top bar's search; a page per book; a modal to add or
# edit one, filled in from a barcode scan or a typed ISBN (lookup). A
# book's status is BookStatusesController's.
class BooksController < ApplicationController
  include SearchableIndex

  before_action :set_book, only: %i[show edit update destroy]
  rate_limit_per_person to: 10, within: 1.minute, only: :lookup

  def index
    authorize Book
    query = Books::IndexQuery.new(viewer: current_profile, params: params.permit(:q, :status, :genre, :sort, :shelf), page: params[:page])

    render_searchable_index(page: Views::Books::Index.new(query: query),
                            results: Views::Books::List.new(query: query))
  end

  def show
    authorize @book

    render_page Views::Books::Show.new(book: @book, viewer: current_profile)
  end

  def new
    @book = Book.new(profile: current_profile)
    authorize @book

    render_modal(form_view(@book), page: books_path)
  end

  # The camera. What it reads goes to #lookup, like a typed ISBN.
  def scanner
    authorize Book, :scan?

    render_modal(Views::Books::Modals::Scan.new(wasm_url: helpers.asset_path("zxing_reader.wasm")), page: books_path)
  end

  # The form for an ISBN, filled in with what the catalogues know
  # (Books::Lookup: Open Library, then Google Books): from the
  # scanner, the scan modal's typed ISBN, or the form's own "Look up" (which
  # brings the fields typed so far, to the book's own address when it's an
  # edit). Not a GET: each lookup spends one of the household's day.
  def lookup
    authorize Book, :lookup?
    @book = params[:id].present? ? current_profile.books.find(params[:id]) : Book.new(profile: current_profile)

    isbn = Book::Isbn.normalize(params[:isbn].presence || params.dig(:book, :isbn))
    return refuse(t("books.lookup.invalid_isbn")) unless isbn

    @book.assign_attributes(book_params) if params[:book].present?

    if (existing = current_profile.books.where.not(id: @book.id).find_by(isbn: isbn))
      return render turbo_stream: [ close_modal, toast(:notice, t("books.lookup.already_there", title: existing.title)) ]
    end

    result = Books::Lookup.call(isbn, allowance: Books::LookupAllowance.new(current_profile.household))
    @book.assign_attributes(result.attributes) if result.success?
    @book.isbn = isbn
    previous = @book.assign_next_volume if result.success?

    render turbo_stream: redraw_modal(form_view(@book, lookup: result, volume_after: previous))
  end

  def edit
    authorize @book

    render_modal(form_view(@book), page: @book)
  end

  def create
    @book = Book.new(book_params.merge(profile: current_profile))
    authorize @book

    if @book.save
      Books::Broadcaster.changed(@book)
      redirect_back_after_save(books_path, notice: t("books.notices.created"))
    else
      render turbo_stream: redraw_modal(form_view(@book)), status: :unprocessable_content
    end
  end

  def update
    authorize @book

    if @book.update(book_params)
      Books::Broadcaster.changed(@book)
      redirect_back_after_save(book_path(@book), notice: t("books.notices.updated"))
    else
      render turbo_stream: redraw_modal(form_view(@book)), status: :unprocessable_content
    end
  end

  def destroy
    authorize @book

    viewers = @book.people_with_access
    @book.destroy!
    Books::Broadcaster.changed(@book, viewers)

    redirect_after_destroy(book_path(@book), list: books_path, notice: t("books.notices.destroyed"))
  end

  private

  def set_book
    @book = policy_scope(Book).with_everything.find(params[:id])
  end

  def book_params
    params.expect(book: %i[title author isbn genre_list status started_on finished_on rating notes cover_id cover_url volume])
  end

  def form_view(book, lookup: nil, volume_after: nil)
    Views::Books::Modals::Form.new(
      book: book, url: book.persisted? ? book_path(book) : books_path, lookup: lookup, volume_after: volume_after,
      genre_suggestions: Book.genre_counts(Book.accessible_by(current_profile)).map(&:first)
    )
  end
end
