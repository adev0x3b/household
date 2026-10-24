# frozen_string_literal: true

# One book: the cover large, everything known about it, and, for its owner,
# its status as pills to tap. Editing and sharing it are the top bar's, for
# whoever may change it, with deleting behind its "more".
class Views::Books::Show < Views::Base
  include Phlex::Rails::Helpers::TurboStreamFrom

  def initialize(book:, viewer:)
    @book = book
    @viewer = viewer
  end

  def page_title = @book.display_title

  def navbar_controls
    return unless Pundit.policy!(@viewer, @book).update?

    actions = [
      Components::Action.new(href: routes.edit_book_path(@book), icon: "fa-pen", label: t("books.show.edit"), turbo_stream: true),
      Components::Action.new(href: routes.new_book_share_path(book_id: @book.id), icon: "fa-share-nodes",
                             label: t("books.show.share"), turbo_stream: true),
      Components::Action.new(href: routes.book_path(@book), icon: "fa-trash", label: t("books.show.destroy"), method: :delete,
                             confirm: t("books.confirm_destroy", title: @book.title), danger: true)
    ]
    Components::PageControls.new(actions: actions)
  end

  def view_template
    div(class: "book-show") do
      turbo_stream_from @viewer, :books
      render Components::PageHeader.new(title: @book.display_title, back_href: books_path, back_label: t("books.show.back"))

      div(class: "book-show__main") do
        div(class: "book-show__cover") { render Views::Books::Cover.new(book: @book, size: "L") }
        div(class: "book-show__details") do
          p(class: "book-show__author") { @book.author }
          status_control
          facts
          notes
          shared_line
          attribution
        end
      end
    end
  end

  private

  def owner? = @book.profile_id == @viewer.id

  def status_control
    if owner?
      items = Book::STATUS_ORDER.map do |status|
        Components::NavItem.new(key: status, href: book_status_path(@book, status: status), label: t("books.status.#{status}"),
                                icon: Views::Books::StatusBadge.icon(status))
      end
      render Components::SegmentedFilter.new(items: items, current: @book.status, label: t("books.show.status_label"), method: :patch)
    else
      render Views::Books::StatusBadge.new(status: @book.status)
    end
  end

  def facts
    dl(class: "book-show__facts") do
      fact(:genres) { genre_links } if @book.genres.any?
      fact(:isbn) { @book.isbn } if @book.isbn
      fact(:started_on) { l(@book.started_on, format: :long) } if @book.started_on
      fact(:finished_on) { l(@book.finished_on, format: :long) } if @book.finished_on
      fact(:rating) { render Views::Books::Rating.new(rating: @book.rating, class_name: "book-show__rating") } if @book.rating
    end
  end

  def fact(key, &)
    div(class: "book-show__fact") do
      dt { t("books.show.facts.#{key}") }
      dd(&)
    end
  end

  def genre_links
    @book.genres.each do |genre|
      a(href: books_path(genre: genre, shelf: (owner? ? nil : @book.profile_id)), class: "genre-chip") { span { genre } }
    end
  end

  def notes
    return if @book.notes.blank?

    section(class: "book-show__notes", aria: { label: t("books.show.notes") }) do
      h2(class: "book-show__section-title") { t("books.show.notes") }
      p { @book.notes }
    end
  end

  # The owner sees who they shared it with; a housemate sees whose it is.
  def shared_line
    if owner?
      names = @book.shared_profiles.map(&:display_name)
      return if names.empty?

      text = t("books.show.shared_with", names: names.to_sentence)
    else
      text = t("books.show.shared_by", name: @book.profile.display_name)
    end

    p(class: "book-show__shared") do
      render Components::Icon.new("fa-user-group")
      span { text }
    end
  end

  # Courtesy to where the data and the cover come from.
  def attribution
    case @book.cover_source
    when :open_library
      p(class: "book-show__attribution") do
        a(href: @book.open_library_url || "https://openlibrary.org", target: "_blank", rel: "noopener noreferrer") { t("books.show.open_library") }
      end
    when :google_books
      p(class: "book-show__attribution") { t("books.show.google_books") }
    end
  end
end
