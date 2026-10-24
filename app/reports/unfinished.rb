# frozen_string_literal: true

module Reports
  # Every day that has passed and is still to do, of every kind and however
  # long ago: neither done, cancelled nor skipped. A saved day still pending
  # or in progress, and a scheduled day of a series nothing was ever saved
  # about. "Needs attention" lists them all, since a dose missed last spring
  # is still a dose someone should record.
  # Each section asks for its own kinds (`entries(of: Medication)`) and
  # words them; the page's Window keeps one, so the reads are shared.
  #
  # Apart from the window's loads on purpose: the window loads every day of
  # a span, done ones included, for the period's figures; this reads back
  # however long ago but loads only the unfinished, and of their series
  # only what naming a day reads (Details::Base.label_preloads). A day
  # nothing was saved about is looked for only from the first day its
  # series may have one (Event#unsaved_since), and which days from there
  # were saved is read as bare keys (`pluck`), never rows, so a series
  # with years of done days costs the days since its last gap.
  #
  # Like the window, it loads a kind when first asked for it, and the kinds
  # a page names (`together`, the window's) at once: the overview's
  # sections ask one after another and read once.
  #
  #   Unfinished.new(audience, today:).entries(of: Appointment) { _1.section == :agenda }
  #   Unfinished.new(audience, today:).latest(of: Medication)   # [[newest entry, how many], …], one per series
  class Unfinished
    def initialize(audience, today:, together: [])
      @audience = audience
      @today = today
      @together = together
      @loaded = {}
    end

    # The unfinished days of the kinds `of` whose series `select` keeps,
    # oldest first, as ledger entries (state :missed).
    def entries(of: Event.types, &select)
      kinds = Array(of)
      missing = kinds - @loaded.keys
      missing |= @together - @loaded.keys if missing.intersect?(@together)
      load(missing)
      kinds.flat_map { @loaded.fetch(_1) }.select { |entry| select.nil? || yield(entry.event) }.sort_by { |entry| [ entry.date, entry.time.to_s ] }
    end

    # One per series, newest first: its newest unfinished day and how many
    # it has, so a dose missed every day for a week is one line, not seven.
    def latest(of: Event.types, &select)
      entries(of: of, &select).group_by { |entry| entry.event.id }.values
        .map { |days| [ days.last, days.size ] }.sort_by { |entry, _| [ -entry.date.jd, entry.time.to_s ] }
    end

    private

    def load(kinds)
      return if kinds.empty?

      scope = @audience.events.where(type: kinds.map(&:name), starts_on: ...@today)
      open = Occurrence.where(event_id: scope.select(:id), date: ...@today, status: %i[pending in_progress]).to_a
      series = Event.preload_series(series_to_read(scope, open), names_only: true)
      # The list asks each day's policy whether the viewer may settle it, which reads the series' shares
      ActiveRecord::Associations::Preloader.new(records: series, associations: [ :event_shares, { collection: :collection_shares } ]).call
      by_id = series.index_by(&:id)
      open.each { |day| day.event = by_id.fetch(day.event_id) }
      Occurrence.preload_details(open, names_only: true)

      past = Occurrence.from_unsaved_since.where(event_id: by_id.keys, date: ...@today)
      days = (open + unsaved(series, saved_keys(past))).group_by { |day| day.event.class }
      kinds.each do |kind|
        @loaded[kind] = days.fetch(kind, []).map { |day| OccurrenceLedger::Entry.new(occurrence: day, state: :missed) }
      end
    end

    # The series whose days can be unfinished: a repeating one (its days
    # nothing was saved about), a one-off with no row at all (its one day),
    # and those of the open days. A one-off whose day was saved is done
    # with unless that day is open: most of a household's series, never
    # loaded.
    def series_to_read(scope, open)
      scope.where.not(rrule: nil).or(scope.without_saved_days).or(scope.where(id: open.map(&:event_id)))
    end

    # The [date, "HH:MM"] of each saved day given, by series.
    def saved_keys(past)
      past.pluck(:event_id, :date, :time).each_with_object(Hash.new { |keys, id| keys[id] = Set.new }) do |(id, date, time), keys|
        keys[id] << [ date, time&.strftime("%H:%M") ]
      end
    end

    def unsaved(series, keys)
      series.flat_map { |event| event.unsaved_days_between(event.unsaved_since, @today - 1, keys[event.id]) }
    end
  end
end
