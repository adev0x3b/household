# frozen_string_literal: true

# The languages kaikki.org has an extract of, for the admin page's "Add a
# language" list: its name (what the download URL uses) and how many word
# senses it has, biggest first. Read from https://kaikki.org/dictionary/ and
# cached for a day — or read again each time when the cache itself fails
# (a cache store that isn't set up mustn't break the admin page).
#
#   Lexicon::Catalog.languages  # => [#<Entry name="English" senses=1787236>, …]
module Lexicon
  class Catalog < ApplicationClient
    class Error < ApplicationClient::Error; end

    URL = "https://kaikki.org/dictionary/"
    CACHE_KEY = "lexicon/catalog/v1"
    LINK = %r{<a href="([^"/]+)/index\.html">([^<]+?) \(([\d,]+) senses\)</a>}

    Entry = Data.define(:name, :senses)

    def self.service = "kaikki.org"

    # [] when kaikki.org can't be asked: the page offers no language then.
    def self.languages
      begin
        Rails.cache.fetch(CACHE_KEY, expires_in: 1.day, skip_nil: true) { parse(download) }
      rescue Error
        raise
      rescue StandardError => e
        Rails.error.report(e, handled: true, context: { step: "the catalog's cache: read without it" })
        parse(download)
      end
    rescue Error
      []
    end

    def self.parse(html)
      html.to_s.scan(LINK).filter_map do |_, name, senses|
        name = CGI.unescapeHTML(name)
        next if name.start_with?("All languages")

        Entry.new(name: name, senses: senses.delete(",").to_i)
      end.uniq(&:name).sort_by { -_1.senses }
    end

    def self.download = text(perform(get(URL)))
  end
end
