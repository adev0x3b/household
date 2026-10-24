# frozen_string_literal: true

module Calendar
  # The days the calendar draws: every day of every series a profile sees
  # between two dates, saved or projected (Event#occurrences_between) — one
  # per slot for a series taken several times a day, plus the saved days
  # off its schedule — each date's in one order, the series' then the
  # slot's (a day card sorts them further, keeping it for ties).
  #
  #   Calendar::Days.between(profile, from, to)   # => { Date => [Occurrence] }, the month view or the cards a change redraws
  #   Calendar::Days.on(profile, date)            # => [Occurrence], one date's
  #   Calendar::Days.on_date(events, date)        # => [Occurrence], from series already loaded
  class Days
    # What a card reads of its series besides the days: whose it is, who
    # it is shared with, its collection's sharees.
    CARD_PRELOADS = [ :profile, :event_shares, { collection: :collection_shares } ].freeze

    # The series `profile` sees that may have a day between two dates.
    def self.series(profile, from, to)
      Event.visible_in(from, to).accessible_by(profile).includes(*CARD_PRELOADS)
    end

    def self.between(profile, from, to)
      data = Hash.new { |hash, date| hash[date] = [] }
      Event.preload_occurrences(series(profile, from, to), from, to).sort_by(&:id).each do |event|
        event.occurrences_between(from, to).each { |occurrence| data[occurrence.date] << occurrence }
      end
      preload_for_cards(data.values.flatten)
      data
    end

    def self.on(profile, date) = between(profile, date, date)[date] || []

    # The date's days of series loaded with their days there (a
    # Reports::Window's), with what their cards read.
    def self.on_date(events, date)
      days = events.sort_by(&:id).flat_map { |event| event.occurrences_between(date, date) }
      ActiveRecord::Associations::Preloader.new(records: days.map(&:event).uniq, associations: CARD_PRELOADS).call
      preload_for_cards(days)
      days
    end

    # What each kind's card reads beyond its series (Event.preload_for_cards:
    # a lab result's values, what a payment pays for), a kind at a time.
    def self.preload_for_cards(days)
      days.group_by { |day| day.event.class }.each { |kind, group| kind.preload_for_cards(group) }
    end
  end
end
