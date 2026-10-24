# frozen_string_literal: true

# After a series changed, redraws the day cards it touches for everyone who
# sees it (Event#audience, plus `extra_profiles` — the audience before the
# change), in the months they have open (CalendarWatch: known to every
# process, so a job pushes them as a request does). A month's page shows
# the days of the months beside it that fill its first and last weeks, so
# its room gets those days' cards too. `dates`: days the series just left
# (a day moved, deleted), redrawn too.
module Calendar
  class DayCardBroadcaster < ApplicationBroadcaster
    def self.call(**) = new(**).call

    def initialize(event:, dates: [], extra_profiles: [])
      @event = event
      @dates = Array(dates).compact.map(&:to_date)
      @extra_profiles = extra_profiles
    end

    def call
      quietly do
        watched = CalendarWatch.months_by_profile(profiles.map(&:id))
        profiles.each do |profile|
          watched.fetch(profile.id, []).each do |year_month|
            month = month_of(year_month)
            broadcast(profile, dates_shown_with(month), month: month, room: "profile_#{profile.id}:#{year_month}")
          end
        end
      end
    end

    private

    attr_reader :event, :dates, :extra_profiles

    def profiles = @profiles ||= (event.audience + extra_profiles).uniq

    def month_of(year_month)
      year, month = year_month.split("-").map(&:to_i)
      Calendar::Month.new(Date.new(year, month, 1))
    end

    # The days of the series on a month's page, and the days it left there.
    def dates_shown_with(month)
      shown = month.shown
      left = dates.select { |date| shown.cover?(date) }
      return left.uniq if event.destroyed?

      (event.occurrences_between(shown.first, shown.last).map(&:date) + left).uniq
    end

    # In the recipient's language and on their clock, not the editor's. The
    # cards' days are read once for all of them, so a series with a day on
    # every date of the page costs no more than one with a single day.
    def broadcast(profile, dates, month:, room:)
      return if dates.empty?

      as(profile) do
        days = Calendar::Days.between(profile, dates.min, dates.max)
        dates.each do |date|
          day_card = Views::Calendar::DayCard.new(date: date, occurrences: days[date], today: date == Date.current,
                                                  beside: month.beside?(date), viewer: profile)
          broadcast_to_room(room, :replace, day_card, target: "day_#{date.iso8601}")
        end
      end
    end
  end
end
