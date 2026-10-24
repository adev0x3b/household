# frozen_string_literal: true

# The shelf's discrete choices, the sort and whose shelf when housemates
# shared theirs, as a form that visits the page again (keeping the search,
# status and genre), like the statistics member filter.
class Views::Books::Filters < Views::Base
  SORT_ICONS = { "recent" => "fa-clock", "title" => "fa-arrow-down-a-z", "author" => "fa-user-pen", "finished" => "fa-flag-checkered" }.freeze

  def initialize(query:)
    @query = query
  end

  def view_template
    filters = @query.filters

    render Components::AutoSubmitForm.new(url: books_path, dom_id: "books_filters", html_class: "book-filters", turbo_action: "replace") do |form|
      { q: filters.q, status: filters.status, genre: filters.genre }.compact_blank.each do |name, value|
        input(type: "hidden", name: name, value: value)
      end

      label(class: "book-filters__field") do
        span(class: "is-sr-only") { t("books.index.sort.label") }
        div(class: "select is-small") do
          form.select_field(name: "sort") do
            Book::SORTS.each_key { |key| option(value: key, selected: key == filters.sort) { t("books.index.sort.#{key}") } }
          end
        end
      end

      if @query.shared?
        label(class: "book-filters__field") do
          span(class: "is-sr-only") { t("books.index.shelf.label") }
          div(class: "select is-small") do
            form.select_field(name: "shelf") do
              option(value: "mine", selected: filters.shelf == "mine") { t("books.index.shelf.mine") }
              @query.owners.each { |owner| option(value: owner.id, selected: filters.shelf == owner.id.to_s) { t("books.index.shelf.owner", name: owner.display_name) } }
              option(value: "everyone", selected: filters.shelf == "everyone") { t("books.index.shelf.everyone") }
            end
          end
        end
      end
    end
  end
end
