# frozen_string_literal: true

# A book's details. The ISBN field's "Look up" asks the catalogues
# (Books::Lookup) and comes back with the form filled in
# (BooksController#lookup, this same form sent through the button's
# formaction, no script); `lookup` says how that went and from which
# source.
class Views::Books::Modals::Form < Views::Base
  NOTICE_TONES = { found: :neutral, not_found: :action, unavailable: :action, capped: :action }.freeze

  def initialize(book:, url:, lookup: nil, volume_after: nil, genre_suggestions: [])
    @book = book
    @url = url
    @lookup = lookup
    @volume_after = volume_after
    @genre_suggestions = genre_suggestions
  end

  def view_template
    render Components::Modal.new(size: :medium, section: :bookshelf) do |modal|
      modal.modal_header(title: title, subtitle: subtitle, icon: "fa-book")

      render Components::Form.new(record: @book, url: @url, submit_text: submit_text, modal: modal) do |f|
        lookup_notice
        isbn_field(f)
        text_field(f, :title, autofocus: @book.title.blank?)
        volume_field(f)
        text_field(f, :author)
        genres_field(f)
        status_field(f)
        dates_fields(f)
        rating_field(f)
        notes_field(f)
        cover_field(f)
      end
    end
  end

  private

  def title = @book.persisted? ? t("books.form.edit_title") : t("books.form.new_title")
  def subtitle = @book.persisted? ? t("books.form.edit_subtitle") : t("books.form.new_subtitle")
  def submit_text = @book.persisted? ? t("books.form.update") : t("books.form.create")

  # Sent with the form's own method, so an edit's lookup is a PATCH of the
  # book's address and a new book's a POST.
  def lookup_path = @book.persisted? ? lookup_book_path(@book) : lookup_books_path

  # How the lookup went: found (and where), not found, nobody answering, the day's lookups spent.
  def lookup_notice
    return unless @lookup

    render Components::Notice.new(tone: NOTICE_TONES.fetch(@lookup.error || :found, :neutral)) do
      p { @lookup.success? ? t("books.lookup.found", source: t("books.sources.#{@lookup.source}")) : t("books.lookup.#{@lookup.error}") }
    end
  end

  def isbn_field(f)
    form_field(f, :isbn, label: t("books.form.isbn_label"), help: t("books.form.isbn_help"), control: false) do |field|
      div(class: "field has-addons book-form__isbn") do
        div(class: "control is-expanded") do
          f.text_field :isbn, class: "input is-medium", inputmode: "numeric", autocomplete: "off",
                              placeholder: t("books.form.isbn_placeholder"), aria: field.aria
        end
        div(class: "control") do
          button(type: "submit", class: "button is-medium book-form__lookup", formaction: lookup_path, formnovalidate: true,
                 data: { turbo_stream: true }, title: t("books.form.lookup")) do
            render Components::Icon.new("fa-magnifying-glass")
            span { t("books.form.lookup") }
          end
        end
      end
    end
  end

  def text_field(f, attribute, autofocus: false)
    form_field(f, attribute, label: t("books.form.#{attribute}_label")) do |field|
      f.text_field attribute, class: "input is-medium", placeholder: t("books.form.#{attribute}_placeholder"),
                              autofocus: autofocus, required: required_attribute?(@book, attribute), aria: field.aria
    end
  end

  # A series' volume: the number proposed after the shelf's last one says so.
  def volume_field(f)
    form_field(f, :volume, label: t("books.form.volume_label"), help: volume_help) do |field|
      f.number_field :volume, class: "input", min: 1, step: 1, inputmode: "numeric", placeholder: t("books.form.volume_placeholder"), aria: field.aria
    end
  end

  def volume_help
    @volume_after ? t("books.form.volume_suggested", previous: @volume_after) : t("books.form.volume_help")
  end

  def genres_field(f)
    form_field(f, :genre_list, label: t("books.form.genres_label"), help: t("books.form.genres_help")) do |field|
      f.text_field :genre_list, class: "input is-medium", placeholder: t("books.form.genres_placeholder"), list: "book_genres", autocomplete: "off", aria: field.aria
      datalist(id: "book_genres") { @genre_suggestions.each { |genre| option(value: genre) } }
    end
  end

  def status_field(f)
    form_field(f, :status, label: t("books.form.status_label"), select: true) do |field|
      f.select :status, select_options(Book.statuses.keys) { |key| t("books.status.#{key}") }, {}, aria: field.aria
    end
  end

  def dates_fields(f)
    div(class: "book-form__dates") do
      %i[started_on finished_on].each do |attribute|
        form_field(f, attribute, label: t("books.form.#{attribute}_label")) do |field|
          f.date_field attribute, class: "input", aria: field.aria
        end
      end
    end
  end

  def rating_field(f)
    form_field(f, :rating, label: t("books.form.rating_label"), select: true) do |field|
      f.select :rating, [ [ t("books.form.rating_none"), "" ] ] + Book::RATINGS.map { |stars| [ Views::Books::Rating.stars(stars), stars ] }, {}, aria: field.aria
    end
  end

  def notes_field(f)
    form_field(f, :notes, label: t("books.form.notes_label")) do |field|
      f.text_area :notes, class: "textarea", rows: 3, placeholder: t("books.form.notes_placeholder"), aria: field.aria
    end
  end

  # The cover URL is the stored one, never the address Book#cover_url
  # builds for an Open Library cover, which isn't a URL the book may keep.
  def cover_field(f)
    f.hidden_field :cover_id
    f.hidden_field :cover_url, value: @book[:cover_url]
    return unless @book.cover?

    div(class: "book-form__cover") do
      render Views::Books::Cover.new(book: @book, size: "M")
      p(class: "help") { t("books.form.cover_help") }
    end
  end
end
