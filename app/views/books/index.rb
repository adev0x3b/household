# frozen_string_literal: true

# The shelf: the sort and whose-shelf pickers (outside the results frame,
# full-page visits), then the results frame with the status pills, the
# genre chips and the cover grid. The search, adding a book, the scanner
# and sharing the shelf are the top bar's.
class Views::Books::Index < Views::Base
  include Phlex::Rails::Helpers::TurboStreamFrom

  def initialize(query:)
    @query = query
  end

  def page_title = t("books.index.title")

  # The search sends the other filters as hidden fields, so a search keeps
  # them; the search itself is the field being typed into.
  def navbar_controls
    search = Components::IndexSearch.new(url: routes.books_path, results: Views::Books::List, query: @query.filters.q,
                                         placeholder: t("books.index.search_placeholder"), hidden: @query.filters.to_params.except(:q))
    actions = [
      Components::Action.new(href: routes.new_book_path, icon: "fa-plus", label: t("books.index.new"), turbo_stream: true),
      Components::Action.new(href: routes.scanner_books_path, icon: "fa-barcode", label: t("books.index.scan"), turbo_stream: true),
      Components::Action.new(href: routes.new_bookshelf_share_path, icon: "fa-share-nodes", label: t("books.index.share_shelf"), turbo_stream: true)
    ]
    Components::PageControls.new(search: search, actions: actions)
  end

  def view_template
    div(class: "books") do
      turbo_stream_from @query.viewer, :books
      div(class: "books__header") do
        render Components::PageHeader.new(title: t("books.index.title"))
        render Views::Books::Filters.new(query: @query)
      end
      render Views::Books::List.new(query: @query)
    end
  end
end
