# frozen_string_literal: true

module Books
  # What Google Books knows about an ISBN — the second source, for the
  # editions Open Library doesn't have (most Italian ones). Two steps,
  # because the Books API's own search answers "0 results" to `isbn:`
  # queries for whole projects at a time (seen 2026-10-07, even for Dune):
  #
  #   1. the keyless Dynamic Links endpoint (books.google.com/books?bibkeys=
  #      ISBN:…&jscmd=viewapi) resolves the ISBN to a volume id — it knew
  #      every Italian ISBN tried, down to small publishers;
  #   2. GET volumes/<id> with the API key gives title, authors, categories
  #      and whether there is a cover.
  #
  # Needs a key — Platform.google_books_api_key: /admin/settings, else
  # GOOGLE_BOOKS_API_KEY (free, 1,000 queries a day): without a
  # key Google shares one daily quota among everyone and answers 429, so it
  # isn't even asked. The cover is hotlinked from Google, like Open
  # Library's, from a URL built on the volume id (Book#cover_url).
  #
  #   Books::GoogleBooks.configured?             # => true when a key is set
  #   Books::GoogleBooks.lookup("9788807091971") # => Books::Answer
  class GoogleBooks < ApplicationClient
    class Error < ApplicationClient::Error; end

    DYNAMIC_LINKS = "https://books.google.com/books"
    API = "https://www.googleapis.com/books/v1/volumes"
    COVER = "https://books.google.com/books/content?id=%s&printsec=frontcover&img=1&zoom=1&source=gbs_api"
    FIELDS = "volumeInfo(title,subtitle,authors,categories,imageLinks)"
    GENRES = 5

    def self.service = "Google Books"
    def self.key = Platform.google_books_api_key
    def self.configured? = key.present?

    def self.lookup(isbn)
      return Answer.none(:unavailable) unless configured?

      id = resolve(isbn) or return Answer.none(:not_found)
      volume = json(perform(request("#{API}/#{id}?#{{ key: key, fields: FIELDS }.to_query}")))["volumeInfo"]
      volume.is_a?(Hash) ? Answer.new(attributes: to_attributes(volume, id), reason: :found) : Answer.none(:not_found)
    rescue Error => e
      Rails.error.report(e, handled: true, severity: :warning, context: { isbn: isbn })
      Answer.none(:unavailable)
    end

    # The volume id Google files the ISBN under, or nil. The answer is JSONP
    # (`x({...});`), the object empty when the ISBN is unknown.
    def self.resolve(isbn)
      body = perform(request("#{DYNAMIC_LINKS}?#{{ bibkeys: "ISBN:#{isbn}", jscmd: "viewapi", callback: "x" }.to_query}")).body.to_s
      found = body[/\{.*\}/m] or raise Error, "#{service}' Dynamic Links answered with something that isn't JSON"
      JSON.parse(found).dig("ISBN:#{isbn}", "info_url").to_s[/[?&]id=([^&]+)/, 1]
    rescue JSON::ParserError
      raise Error, "#{service}' Dynamic Links answered with something that isn't JSON"
    end

    def self.to_attributes(volume, id)
      {
        title: [ volume["title"], volume["subtitle"] ].compact_blank.map(&:squish).join(": "),
        author: Array(volume["authors"]).map(&:squish).compact_blank.join(", "),
        genres: Array(volume["categories"]).flat_map { |category| category.to_s.split(" / ") }.map(&:squish).compact_blank
          .reject { |genre| genre.casecmp?("General") }.uniq(&:downcase).first(GENRES), # "General" is BISAC filler, not a genre
        cover_url: (format(COVER, id) if volume["imageLinks"].present?)
      }.compact_blank
    end

    def self.request(url) = get(url, "User-Agent" => OpenLibrary::USER_AGENT, "Accept" => "application/json")
    private_class_method :resolve, :to_attributes, :request
  end
end
