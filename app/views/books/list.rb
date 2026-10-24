# frozen_string_literal: true

# The shelf's results frame, rendered with the page and on its own as the
# answer to the navbar search. The status pills
# and the genre chips sit inside it so their counts follow the search;
# they revisit the page (the frame targets _top) with `data-turbo-action=
# "replace"`: a page refresh, morphed with the scroll kept, so the whole
# page, navbar search included, always agrees on the filters.
class Views::Books::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "books_results"

  def initialize(query:)
    @query = query
  end

  def view_template
    turbo_frame_tag(FRAME_ID, class: "index-results", target: "_top") do
      status_pills
      genre_chips
      grid
      render Components::Pagination.new(collection: @query.books, turbo_frame: FRAME_ID, turbo_action: "advance")
    end
  end

  private

  def filters = @query.filters

  def status_pills
    items = [ Components::NavItem.new(key: "all", href: books_path(filters.to_params.except(:status)), label: t("books.index.all"), count: @query.total) ]
    items += Book::STATUS_ORDER.map do |status|
      Components::NavItem.new(key: status, href: books_path(filters.to_params.merge(status: status)), label: t("books.status.#{status}"),
                              count: @query.status_counts.fetch(status, 0), icon: Views::Books::StatusBadge.icon(status))
    end
    render Components::SegmentedFilter.new(items: items, current: filters.status || "all", label: t("books.index.status_label"))
  end

  def genre_chips
    genres = @query.genres
    return if genres.size < 2 && filters.genre.nil?

    render Components::ScrollRow.new do
      nav(class: "genre-chips", aria: { label: t("books.index.genres_label") }) do
        genres.each { |genre, count| genre_chip(genre, count) }
      end
    end
  end

  def genre_chip(genre, count)
    active = genre == filters.genre
    a(href: books_path(filters.to_params.merge(genre: active ? nil : genre).compact), class: [ "genre-chip", ("is-current" if active) ],
      aria: { current: (active ? "true" : nil) }, data: { turbo_action: "replace" }) do
      span { genre }
      span(class: "genre-chip__count") { count }
    end
  end

  def grid
    books = @query.books

    div(class: "books__grid", id: "books_grid") do
      if books.any?
        books.each { |book| render Views::Books::Card.new(book: book, viewer: @query.viewer) }
      else
        render Components::EmptyState.new(id: "books_empty", icon: "fa-book", message: empty_message)
      end
    end
  end

  def empty_message
    case @query.empty_reason
    when :search then t("books.index.empty_search")
    when :genre then t("books.index.empty_genre", genre: filters.genre)
    when :status then t("books.index.empty_status.#{filters.status}")
    else filters.shelf == "mine" ? t("books.index.empty") : t("books.index.empty_shelf")
    end
  end
end
