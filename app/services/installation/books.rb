# frozen_string_literal: true

module Installation
  # The bookshelf's outside sources, as one form: a step of the first setup
  # and a card on /admin/settings. The Google Books key is a secret: it is
  # never shown back, and a blank field keeps the saved one.
  #
  #   books = Installation::Books.current.assign(params)
  #   books.valid?
  #   books.apply_to(setting)   # the Platform::Setting row, left unsaved
  class Books
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :google_books_api_key, :string
    attribute :book_lookups_per_day, :integer

    validates :book_lookups_per_day, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

    def self.param_key = :books

    def self.fields = attribute_names.map(&:to_sym)

    def self.current = new(book_lookups_per_day: Platform.book_lookups_per_day)

    # The first setup starts from the same values: the environment's and the defaults.
    def self.for_setup = current

    def assign(values)
      given = values.to_h.symbolize_keys
      self.google_books_api_key = given[:google_books_api_key].to_s.strip.presence
      self.book_lookups_per_day = given[:book_lookups_per_day].presence if given.key?(:book_lookups_per_day)
      self
    end

    def apply_to(setting)
      setting.google_books_api_key = google_books_api_key if google_books_api_key.present?
      setting.book_lookups_per_day = book_lookups_per_day
      setting
    end

    # Always a step of the first setup.
    def asked?(_form) = true
  end
end
