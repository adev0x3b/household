# frozen_string_literal: true

module Books
  # What Open Library knows about an ISBN, for the new-book form: title,
  # authors, a few subjects as genres, and the cover's id (the cover itself
  # is hotlinked from covers.openlibrary.org by that id, which isn't rate
  # limited; by ISBN it is). Free and keyless; they ask for a User-Agent.
  #
  #   Books::OpenLibrary.lookup("9780306406157")   # => Books::Answer
  #   answer.found?  answer.attributes             # => { title:, author:, genre_list:, cover_id: }
  #
  # The service being down never raises out: the answer is :unavailable,
  # and a line in the log (it is a state, not a fault).
  class OpenLibrary < ApplicationClient
    class Error < ApplicationClient::Error; end

    API = "https://openlibrary.org/api/books"
    # Open Library asks for a way to reach whoever makes the calls.
    USER_AGENT = "Household (https://#{ENV.fetch("APP_HOST", "localhost")}; bookshelf lookup)"
    GENRES = 5

    def self.service = "Open Library"

    def self.lookup(isbn)
      data = json(perform(get("#{API}?bibkeys=ISBN:#{isbn}&jscmd=data&format=json", "User-Agent" => USER_AGENT, "Accept" => "application/json")))["ISBN:#{isbn}"]
      data.is_a?(Hash) ? Answer.new(attributes: to_attributes(data), reason: :found) : Answer.none(:not_found)
    rescue Error => e
      Rails.error.report(e, handled: true, severity: :warning, context: { isbn: isbn })
      Answer.none(:unavailable)
    end

    def self.to_attributes(data)
      {
        title: data["title"].to_s.squish,
        author: Array(data["authors"]).filter_map { |author| author["name"].to_s.squish.presence }.join(", "),
        genre_list: Array(data["subjects"]).filter_map { |subject| subject["name"].to_s.squish.presence }.first(GENRES).join(", "),
        cover_id: cover_id_in(data.dig("cover", "medium") || data.dig("cover", "large") || data.dig("cover", "small"))
      }.compact_blank
    end

    # https://covers.openlibrary.org/b/id/8739161-M.jpg => 8739161
    def self.cover_id_in(url) = url.to_s[%r{/b/id/(\d+)-}, 1]&.to_i
    private_class_method :to_attributes, :cover_id_in
  end
end
