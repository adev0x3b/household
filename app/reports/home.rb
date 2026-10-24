# frozen_string_literal: true

module Reports
  # Entry point for the home dashboard: one instance per request, every
  # report memoized, so a page only pays for what it shows. `period` is what
  # the section pages report on (the last 30 days unless one is picked);
  # everything "as of today" (attention, today, the next 7 days, what's
  # coming up) ignores it.
  #
  # One dashboard of reports per section of the household (Event#section):
  # Agenda (tasks and the appointments that aren't medical), Healthcare,
  # Finance, and Pantry & meals.
  class Home
    attr_reader :audience, :period, :today

    # The overview: everyone's, as of today, and every section at once (what
    # needs attention, the week ahead), so every kind of series is read.
    def self.overview(audience:, today: Date.current, upcoming_page: 1)
      new(audience: audience, today: today, upcoming_page: upcoming_page, kinds: Event.types)
    end

    # `upcoming_page` is the page of the next 7 days shown (Upcoming#page);
    # `kinds` the kinds of series the page reads, loaded together at the
    # first ask (Window#cover) — a section's page leaves them to its reports.
    def initialize(audience:, period: nil, today: Date.current, upcoming_page: 1, kinds: [])
      @audience = audience
      @today = today
      @upcoming_page = upcoming_page
      @kinds = kinds
      @period = period || Period.recent(today: today)
    end

    def agenda
      @agenda ||= Agenda::Dashboard.new(audience: audience, period: period, today: today, window: window)
    end

    def pantry
      @pantry ||= Pantry::Dashboard.new(audience: audience, period: period, today: today, window: window)
    end

    def healthcare
      @healthcare ||= Healthcare::Dashboard.new(audience: audience, period: period, today: today, window: window)
    end

    def finance
      @finance ||= Finance::Dashboard.new(audience: audience, period: period, today: today, window: window)
    end

    # The next 7 days, every section's days together.
    def upcoming
      @upcoming ||= Upcoming.new(audience: audience, today: today, page: @upcoming_page, window: window)
    end

    # Today's days (Occurrences, saved or projected), as the calendar's own
    # day card takes them.
    def today_entries
      @today_entries ||= Calendar::Days.on_date(window.events(today, today), today)
    end

    # No series the viewer can read on any calendar: a household that has
    # just moved in, which the overview offers its first steps instead of
    # empty figures.
    def empty? = !audience.events.exists?

    # Everything to act on, across sections.
    def attention
      @attention ||= AttentionItems.new(
        healthcare.attention, finance.attention, agenda.attention, pantry.attention, today: today,
      )
    end

    private

    # Every report's series and days, loaded once, when the first of them is
    # read, over all they look at: the period and the one before it, the
    # last 30 days (what is overdue or was missed), and as far ahead as the
    # furthest look-ahead, Healthcare's next visits. A report asking outside
    # it still gets its days, for one load more.
    def window
      @window ||= Window.new(audience).cover(
        [ period.previous.start_date, today - Period::RECENT_DAYS ].min,
        [ period.end_date, today + Healthcare::Appointments::UPCOMING_HORIZON_DAYS ].max,
        of: @kinds,
      )
    end
  end
end
