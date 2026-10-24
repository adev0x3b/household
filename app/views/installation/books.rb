# frozen_string_literal: true

# The bookshelf's outside sources (Installation::Books): the Google Books
# key, never shown back, and how many lookups a household gets in a day.
class Views::Installation::Books < Views::Base
  # form: the builder for this section's fields (fields_for), section: the Installation::Books.
  def initialize(form:, section:)
    @form = form
    @section = section
  end

  def view_template
    render Components::Panel.new(title: t("installation.books.title"), hint: t("installation.books.hint")) do
      render Views::Installation::SecretField.new(form: @form, key: :google_books_api_key, label: t("installation.books.google_books_api_key"))
      lookups_field
    end
  end

  private

  def lookups_field
    form_field(@form, :book_lookups_per_day, label: t("installation.books.book_lookups_per_day"),
                                             help: t("installation.books.book_lookups_per_day_help")) do |field|
      @form.number_field :book_lookups_per_day, min: 0, step: 1, inputmode: "numeric", placeholder: t("installation.no_limit"),
                                                class: "input", aria: field.aria
    end
  end
end
