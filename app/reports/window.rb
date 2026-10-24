# frozen_string_literal: true

module Reports
  # The audience's series and their saved days, loaded once for a page:
  # every ledger and list on it takes its series from here and
  # reads their days from memory, instead of each report loading the same
  # series again.
  #
  # It loads by kind, when a report first asks for one, so a page reading
  # only tasks loads only tasks, and a kind loaded once is read by every
  # report after; a page that reads several names them (`cover`'s `of`), and
  # the first ask loads them together. It covers the widest span asked of
  # it: a report asking outside it widens it, and the kinds are loaded again
  # over both. Reports::Home covers the span its reports read up front, so a
  # page loads each kind once.
  #
  #   window = Window.new(audience)
  #   window.events(from, to)                                         # every series with a day there
  #   window.events(from, to, of: Medication)                         # … of some kinds
  #   window.ledger(period, today:, of: Appointment) { _1.section == :healthcare }   # an OccurrenceLedger over them
  #   window.unfinished(today:).entries(of: Task)                     # the days passed and still to do, however old
  class Window
    def initialize(audience)
      @audience = audience
      @loaded = {}
      @together = []
    end

    # Widens the span the loads will cover, so the reports' own asks fall
    # inside it, and names kinds the page reads (`of`), to be loaded
    # together when any of them is first asked for. Loads nothing yet.
    def cover(from, to, of: [])
      widen(from.to_date, to.to_date)
      @together |= Array(of)
      self
    end

    # The series of the kinds `of` (every kind without it) that can have a
    # day between `from` and `to` (by their rule, or a day moved there),
    # their days in the span preloaded.
    def events(from, to, of: Event.types)
      widen(from.to_date, to.to_date)
      kinds = Array(of)
      missing = kinds - @loaded.keys
      missing |= @together - @loaded.keys if missing.intersect?(@together)
      load(missing)
      kinds.flat_map { @loaded.fetch(_1) }
    end

    # The page's Transaction days, for its money sums (TransactionDays#totals),
    # covering the span the series do.
    def transaction_days
      @transaction_days ||= TransactionDays.new(@audience).tap { |days| days.cover(@span) if @span }
    end

    # The days, between the period's dates, of the series of the kinds `of`
    # that `select` keeps (all of them without it).
    def ledger(period, today:, of: Event.types, &select)
      series = events(period.start_date, period.end_date, of: of)
      OccurrenceLedger.new(events: select ? series.select(&select) : series, period: period, today: today)
    end

    # Every day still to do whose date has passed, however long ago
    # (Reports::Unfinished): one read for the page, whichever section asks.
    def unfinished(today:)
      @unfinished ||= {}
      @unfinished[today] ||= Unfinished.new(@audience, today: today, together: @together)
    end

    private

    # A span outside the one loaded drops the loads: each kind is loaded
    # again, over both, when next asked for.
    def widen(from, to)
      return if @span&.cover?(from) && @span.cover?(to)

      @span = @span ? [ @span.begin, from ].min..[ @span.end, to ].max : from..to
      @loaded.clear
    end

    # The kinds' series with a day in the span, with their days there
    # (Event.preload_occurrences): one batch of queries for all of them.
    def load(kinds)
      return if kinds.empty?

      scope = @audience.events.where(type: kinds.map(&:name))
      series = scope.visible_in(@span.begin, @span.end).or(scope.with_saved_in(@span)).includes(:profile)
      by_kind = Event.preload_occurrences(series.to_a, @span.begin, @span.end).group_by(&:class)
      kinds.each { @loaded[_1] = by_kind.fetch(_1, []) }
    end
  end
end
