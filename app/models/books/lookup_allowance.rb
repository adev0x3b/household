# frozen_string_literal: true

module Books
  # How many book lookups a household has left today: the installation's
  # BOOK_LOOKUPS_PER_DAY (Platform.book_lookups_per_day), shared by its
  # members and counted in Solid Cache for the day. Unlimited where the
  # installation sets none. Books::Lookup asks it before going out and
  # spends one each time it does.
  #
  #   allowance = Books::LookupAllowance.new(household)
  #   allowance.left     # => 12, or nil: no limit
  #   allowance.spend!
  class LookupAllowance
    def initialize(household)
      @household = household
    end

    def left
      max = Platform.book_lookups_per_day or return

      [ max - Rails.cache.read(key).to_i, 0 ].max
    end

    def any_left? = left.nil? || left.positive?

    def spend!
      Rails.cache.increment(key, 1, expires_in: 1.day) if Platform.book_lookups_per_day
    end

    private

    def key = "book_lookups:#{@household.id}:#{Date.current.iso8601}"
  end
end
