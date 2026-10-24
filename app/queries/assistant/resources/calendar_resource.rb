# frozen_string_literal: true

module Assistant
  module Resources
    # A kind of series on the calendar, worked with one day at a time. Its
    # records are Occurrences: a saved day, or a projected one of a
    # repeating series (unsaved, `id: nil`), read as the day resolves them
    # (its own value, else the series', Occurrence.resolved_sql). Access
    # goes through the series (Event.accessible_by), so a linked housemate's
    # days are found the way the calendar finds them.
    class CalendarResource < Resource
      MAX_PROJECTED_EVENTS = 200
      # How far ahead a series' next day is looked for. A yearly series has
      # one within this many days; a series with none is simply never due.
      NEXT_DAY_WITHIN = 400

      # The Event subclass the records are days of.
      def type = raise(NotImplementedError, "#{self.class} must say its kind of series")

      def model = Occurrence
      def eventable? = true
      def completable? = true
      def costable? = type.costable?
      def date_column = "occurrences.date"

      def accessible(profile) = Occurrence.accessible_by(profile).of_type(type).with_series(type)

      # A day is seen by whoever sees its series: the calendar's audience.
      def readers(day) = day.event.audience

      # Days by id with what their policies read: the series, its shares and
      # its collection's.
      def where_accessible(profile, ids)
        super.preload(event: [ :event_shares, { collection: :collection_shares } ])
      end

      private

      # One shape for a saved day and a projected one (id nil, upcoming).
      def facts(day, profile)
        event = day.event
        { type: key, id: (day.id if day.persisted?), upcoming: (true if day.new_record?), event_id: event.id,
          date: day.date&.iso8601, time: day.time_string, with: Events::TimesOfDay.word(day.anchor), status: day.status,
          repeats: (Events::RecurrenceRule.describe(event.rrule)[:frequency] if event.recurring?),
          collection: event.collection&.name, owner: owner_name(event, profile) }
      end

      # Whose it is, when it isn't the user's (shared, or a linked housemate's).
      def owner_name(event, profile) = (event.profile.display_name unless event.profile_id == profile.id)

      # A day's series (whose, its collection, its rule, slots and details),
      # its own details, and its cost.
      def read_for_summaries(days)
        load(days, event: %i[profile collection])
        Event.preload_series(days.map(&:event).uniq)
        Occurrence.preload_details(days)
        super
      end

      # A column as the day reads it: its own value, else the series'.
      def columns
        search_columns.map { |column| column.to_s.include?(".") ? column.to_s : Occurrence.resolved_sql(column, type: type) }
      end

      def newest_first(relation) = relation.reorder(Arel.sql("occurrences.date DESC, occurrences.time DESC NULLS LAST, occurrences.id DESC"))

      def filter_collection(relation, collection_id) = relation.where(events: { collection_id: collection_id })

      # Projected days of a range, and series nothing was saved about when
      # no range was given: the days a pending search would otherwise miss.
      def unsaved_matches(profile, words, date_from, date_to, status, collection_id, limit)
        return [] unless status.in?([ nil, "", "pending" ])
        return projected(profile, words, date_from, date_to, collection_id) if date_from && date_to
        return [] if date_from || date_to

        unsaved_series(profile, words, collection_id, limit)
      end

      # The days of repeating series in the range that have no row yet.
      def projected(profile, words, from, to, collection_id)
        events = type.accessible_by(profile).where.not(rrule: nil).visible_in(from, to)
        events = events.where(collection_id: collection_id) if collection_id.present?
        events = Event.preload_occurrences(events.limit(MAX_PROJECTED_EVENTS), from, to)

        days = events.flat_map do |event|
          event.occurrences_between(from, to).select(&:new_record?)
            .select { |day| words.empty? || words.any? { |word| projected_text(day).include?(word) } }
        end
        summarize_all(days, profile: profile)
      end

      # Series with nothing saved yet (made on the calendar, never touched),
      # matched by their own fields, each as its day to act on. A search of
      # the saved days never finds them.
      def unsaved_series(profile, words, collection_id, limit)
        table = type.details_class.table_name
        events = type.accessible_by(profile).without_saved_days
          .joins("LEFT JOIN #{table} #{table}_series ON #{table}_series.event_id = events.id AND #{table}_series.occurrence_id IS NULL")
        events = events.where(collection_id: collection_id) if collection_id.present?
        events = events.where(TextMatch.contains(series_columns, words)) if words.any?
        summarize_all(events.limit(limit).map { |event| day_to_act_on(event) }, profile: profile)
      end

      # The series' own columns (its details' through the series' row).
      def series_columns
        table = type.details_class.table_name
        search_columns.map { |column| Event.column_names.include?(column.to_s) ? "events.#{column}" : "#{table}_series.#{column}" }
      end

      # Today's day or the next one, else the series' first.
      def day_to_act_on(event)
        next_day = event.occurrence_dates_between(Date.current, Date.current + NEXT_DAY_WITHIN).first if event.recurring?
        next_day ? event.occurrence_for(next_day) : event.first_occurrence
      end

      # What a projected day says, for matching words without SQL.
      def projected_text(day)
        values = search_columns.map do |column|
          column = column.to_s.split(".").last
          day.respond_to?(column) ? day.public_send(column) : day.details.try(column)
        end
        TextMatch.fold(values.compact.join(" "))
      end
    end
  end
end
