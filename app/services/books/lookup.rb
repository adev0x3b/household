# frozen_string_literal: true

module Books
  # What is known about an ISBN, from whichever free source has it: Open
  # Library first (keyless), then Google Books when a key is configured
  # (Italian editions are mostly there and not on Open Library). An Open
  # Library hit with no cover or no genres is topped up from Google — it
  # often has both where Open Library has a bare record (Italian manga).
  # One Result, with where it came from.
  #
  # With an `allowance` (Books::LookupAllowance), a lookup is refused once
  # the household's are spent for the day, and spends one otherwise, found
  # or not: the catalogues were asked either way.
  #
  #   result = Books::Lookup.call("9788807091971", allowance: Books::LookupAllowance.new(household))
  #   result.success?  result.source  # => :open_library | :google_books
  #   result.error     # => nil, :not_found, :unavailable or :capped (the household's lookups for today are spent)
  class Lookup
    SOURCES = { open_library: OpenLibrary, google_books: GoogleBooks }.freeze

    Result = ServiceResult.define(:attributes, :source)

    def self.call(isbn, allowance: nil)
      return Result.new(attributes: {}, error: :capped, source: nil) if allowance && !allowance.any_left?

      allowance&.spend!
      answers = []
      SOURCES.each do |name, source|
        next if name == :google_books && !GoogleBooks.configured?

        answer = source.lookup(isbn)
        return Result.new(attributes: with_volume(top_up(answer.attributes, isbn)), error: nil, source: name) if answer.found?

        answers << answer
      end
      # Nobody has it; "unavailable" only when nobody could even be asked.
      error = answers.any? { |answer| answer.reason == :not_found } ? :not_found : :unavailable
      Result.new(attributes: {}, error: error, source: nil)
    end

    # A series' volume number out of the title (Book::Series): "Naruto 27" →
    # Naruto, 27, so every volume shares the series' title.
    def self.with_volume(attributes)
      return attributes if attributes[:title].blank?

      genres = attributes[:genres] || attributes[:genre_list].to_s.split(",")
      parsed = Book::Series.parse(attributes[:title], comics: Book::Series.comics?(genres))
      parsed[:volume] ? attributes.merge(title: parsed[:title], volume: parsed[:volume]) : attributes
    end

    # Open Library's record, with Google's cover and genres where it has none.
    def self.top_up(attributes, isbn)
      missing = []
      missing << :cover_url unless attributes[:cover_id] || attributes[:cover_url]
      missing << :genres if attributes[:genre_list].blank? && attributes[:genres].blank?
      return attributes if missing.empty? || !GoogleBooks.configured?

      extra = GoogleBooks.lookup(isbn)
      return attributes unless extra.found?

      attributes.merge(extra.attributes.slice(*missing).compact_blank)
    end
    private_class_method :with_volume, :top_up
  end
end
