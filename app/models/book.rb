# frozen_string_literal: true

# A book on someone's shelf: what it is (title, author, genres, ISBN, the
# cover Open Library has for it) and where the reader is with it — one
# status at a time, the dates it was started and finished, a rating and
# notes once read. A book is its owner's (books.profile_id); housemates see
# it when the book, or the owner's whole shelf (Bookshelf), is shared with
# them, and never change it.
class Book < ApplicationRecord
  include Searchable
  include Shareable

  searchable_by :title, :author

  MAX_GENRES = 10
  # The one host a cover URL may name: Google Books', for the thumbnails its
  # lookup finds (Open Library's covers are built from cover_id instead).
  COVER_HOST = "books.google.com"
  RATINGS = 1..5
  # The segmented filter's order: what you act on most first.
  STATUS_ORDER = %w[reading want_to_read read dropped].freeze
  # The one-tap action on a card: where a book goes next.
  NEXT_STATUS = { "want_to_read" => "reading", "reading" => "read", "read" => "reading", "dropped" => "reading" }.freeze
  SORTS = {
    "recent" => ->(scope) { scope.order(created_at: :desc, id: :desc) },
    "title" => ->(scope) { scope.order(:title, :volume, :id) },
    "author" => ->(scope) { scope.order(:author, :title, :id) },
    "finished" => ->(scope) { scope.order(Arel.sql("books.finished_on DESC NULLS LAST"), id: :desc) }
  }.freeze

  belongs_to :profile

  shared_through :book_shares

  # The section of the household it belongs to (the share modal's colour).
  def section = :bookshelf

  # Who sees it: its owner, whoever it is shared with, and whoever its
  # owner's whole shelf is shared with.
  def people_with_access = [ *super, *profile.bookshelf&.shared_profiles ].uniq

  enum :status, { want_to_read: 0, reading: 1, read: 2, dropped: 3 }

  normalizes :title, :author, with: ->(value) { value.to_s.squish }
  normalizes :notes, with: ->(value) { value.to_s.strip.presence }
  # An array (the assistant, the seeder) comes out as the same clean list as the
  # form's "Fantasy, Sci-fi" (genre_list=, parsed before the array type casts it).
  normalizes :genres, with: ->(list) { parse_genres(list) }, apply_to_nil: true

  attr_writer :genre_list

  before_validation :normalize_isbn, :normalize_genre_list, :stamp_dates

  validates :title, :author, presence: true
  validates :isbn, uniqueness: { scope: :profile_id }, allow_nil: true
  validate :isbn_well_formed
  validates :rating, numericality: { only_integer: true, in: RATINGS }, allow_nil: true
  validates :volume, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  validate :finished_after_started
  validate :cover_from_google_books

  # One's own, those shared one by one, and every book on a shelf shared whole.
  scope :accessible_by, ->(profile) {
    where_id_in_any(
      unscoped.where(profile_id: profile.id).select(:id),
      BookShare.where(profile_id: profile.id).select(:book_id),
      unscoped.where(profile_id: Bookshelf.where(id: BookshelfShare.where(profile_id: profile.id).select(:bookshelf_id)).select(:profile_id)).select(:id)
    )
  }
  scope :newest_first, -> { SORTS.fetch("recent").call(all) }
  # What its page asks: whom it is shared with, alone or with its whole shelf.
  scope :with_everything, -> { includes(:book_shares, :shared_profiles, profile: { bookshelf: :bookshelf_shares }) }

  # Comma-separated genres, as the form shows and takes them.
  def genre_list = @genre_list || genres.join(", ")

  def self.parse_genres(list)
    Array(list).flat_map { |entry| entry.to_s.split(/[,;]/) }.map(&:squish).compact_blank.uniq(&:downcase).first(MAX_GENRES)
  end

  # Every genre in a scope, most used first: [ [ "Fantasy", 3 ], … ].
  def self.genre_counts(scope)
    scope.unscope(:order).pluck(Arel.sql("unnest(books.genres)")).tally.sort_by { |genre, count| [ -count, genre.downcase ] }
  end

  # "One Piece, vol. 12": the title with the volume number, for a series.
  def display_title = volume ? I18n.t("books.volume_title", title: title, volume: volume) : title

  # What Notifications::Deliver calls the subject of a share.
  def name = display_title

  def next_status = NEXT_STATUS.fetch(status)

  # A volume of a series the owner's shelf already has, read with no number
  # (the catalogue gave none): the next one after theirs is proposed, in
  # memory — the form says so. Returns the volume it follows, or nil.
  def assign_next_volume
    return if volume || title.blank?

    previous = profile.books.where.not(id: id).where(title: title).maximum(:volume) or return
    self.volume = previous + 1
    previous
  end

  # Open Library's cover by id when there is one (M on a card, L on the page),
  # else the cover URL another source gave: Google Books' thumbnail (zoom=1,
  # 128 px wide), which its fife parameter scales up for the page — Google's
  # own zoom=2 is an "image not available" picture for many volumes.
  def cover_url(size = "M")
    return "https://covers.openlibrary.org/b/id/#{cover_id}-#{size}.jpg" if cover_id

    size == "L" ? super()&.then { |url| "#{url}&fife=w400" } : super()
  end

  def cover? = cover_id.present? || self[:cover_url].present?

  # Whom to credit for the cover, and the data that came with it: Open
  # Library for its own covers and for a book it can look up by its ISBN,
  # Google Books for one of its thumbnails. Nil for a book typed by hand.
  def cover_source
    if cover_id.present? || (isbn.present? && self[:cover_url].blank?)
      :open_library
    elsif self[:cover_url].present?
      :google_books
    end
  end

  def open_library_url = isbn && "https://openlibrary.org/isbn/#{isbn}"

  private

  # Hyphens and spaces go; an ISBN-10 becomes 13; what doesn't check out
  # stays as typed, for the validation to name.
  def normalize_isbn
    raw = isbn.to_s.strip
    self.isbn = raw.blank? ? nil : (Isbn.normalize(raw) || raw)
  end

  # The lookup's cover comes back from the form in a hidden field, so it is
  # whatever the request says. Only the CSP's img-src would otherwise keep
  # the page from loading a picture from anywhere.
  def cover_from_google_books
    url = self[:cover_url]
    return if url.blank?

    uri = URI.parse(url)
    errors.add(:cover_url, :invalid) unless uri.is_a?(URI::HTTPS) && uri.host == COVER_HOST
  rescue URI::InvalidURIError
    errors.add(:cover_url, :invalid)
  end

  def isbn_well_formed
    errors.add(:isbn, :invalid) if isbn.present? && !Isbn.valid13?(isbn)
  end

  def normalize_genre_list
    return if @genre_list.nil?

    self.genres = Book.parse_genres(@genre_list)
    @genre_list = nil
  end

  # Starting a book dates it; finishing it too. A book picked up again
  # (read or dropped → reading) starts over. Dates typed by hand win.
  def stamp_dates
    return unless new_record? || status_changed?

    case status
    when "reading"
      if status_was.in?(%w[read dropped])
        self.started_on = Date.current unless started_on_changed?
        self.finished_on = nil unless finished_on_changed?
      else
        self.started_on ||= Date.current
      end
    when "read"
      self.finished_on ||= Date.current
      self.started_on ||= finished_on
    end
  end

  def finished_after_started
    errors.add(:finished_on, :before_start) if started_on && finished_on && finished_on < started_on
  end
end
