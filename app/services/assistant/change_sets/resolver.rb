# frozen_string_literal: true

# Finds the existing record an operation means by `ref`:
#   42                                  an id (or a series' event_id: its occurrence today)
#   "event_id 42 on 2026-09-24"         a series' occurrence on that day (the record, or a
#                                       projected one built unsaved); "event_id 42" alone: today's
#                                       (or, with upcoming: true, its next one from today)
#   "… at 20:00", "… at dinner"         which dose of a day, for a medication taken several
#                                       times a day; without it, the day's first dose still to take
#   "$lab"                              a record created earlier in the same change set
#   "the lab result from last week"     words: dates are read with Assistant::DateWords, the
#                                       rest searched in that type (Assistant::Resources)
#   nil                                 what this chat last worked on, the one in use, else the
#                                       most recent record of that type
# Exactly one match resolves; none or several come back for the model to
# ask about (with candidates). The model never has to guess an id.
#
# In a chat, what the chat itself saved or changed comes first when the
# words don't settle it: right after saving a report, "it", "the report" or
# "the test was done a week ago" (a date the report doesn't have yet) mean
# that report, not a search of every report.
module Assistant
  module ChangeSets
    class Resolver
      # What a ref came to: a record (assumed: the most recent one, taken
      # for a ref that named none), a handle to a record the same set
      # creates, candidates to ask between, or a problem to tell the model.
      Resolution = Data.define(:record, :handle, :candidates, :problem, :assumed) do
        def self.found(record, assumed: false) = new(record:, handle: nil, candidates: [], problem: nil, assumed:)
        def self.handle(name) = new(record: nil, handle: name, candidates: [], problem: nil, assumed: false)
        def self.ambiguous(candidates, problem) = new(record: nil, handle: nil, candidates:, problem:, assumed: false)
        def self.missing(problem) = new(record: nil, handle: nil, candidates: [], problem:, assumed: false)

        def resolved? = record.present? || handle.present?
      end

      # Words that describe the type, not the record.
      STOPWORDS = %w[the my a an of from on at in for this that last latest recent report reports all every result results lab test
                     tests blood value values appointment appointments visit visits purchase purchases payment payments
                     task tasks medication medications dose doses therapy supply supplies range ranges il la lo le gli di del
                     della dal dalla ultimo ultima esame esami risultato risultati visita appuntamento it one questo questa
                     quello quella].freeze
      RECENT = 90.days
      CHAT_CHANGE_SETS = 10
      TIME_SUFFIX = /\s+(?:at|alle|a|di|della|del)\s+(?<time>\S+)\s*\z/i
      ID_ON_DATE = /\A(?<prefix>event[_ ]?id|event|series|id)?\s*[:#=]?\s*(?<id>\d+)(?:[\s,;]+(?:(?:on|date|il)\s*[:=]?\s*)?(?<day>.+))?\z/i

      # The first run of 1-4 words that reads as a date ("last week"; ISO
      # too, "16 September" not), and the text without it. It is also how a
      # delete tells "all my appointments last week" from a name.
      def self.split_date(text)
        iso = text[/\d{4}-\d{2}-\d{2}/]
        return [ Date.iso8601(iso), text.sub(iso, " ") ] if iso

        tokens = text.split
        [ tokens.size, 4 ].min.downto(1) do |length|
          tokens.each_cons(length).with_index do |window, start|
            date = DateWords.parse(window.join(" "))
            return [ date, (tokens[0...start] + tokens[(start + length)..]).join(" ") ] if date
          end
        end
        [ nil, text ]
      end

      def initialize(profile, chat: nil)
        @profile = profile
        @chat = chat
      end

      # upcoming: a change to what the series does from now on (a dose's
      # supplies). A bare series ref then means its next day when there is
      # none today, instead of asking which day.
      def resolve(type, ref, upcoming: false)
        @upcoming = upcoming
        resource = Resources.fetch(type)
        ref, @time = split_time(ref) if resource.doses? && ref.is_a?(String)
        return Resolution.handle(ref.to_s) if ref.to_s.start_with?("$")
        return by_id(resource, ref) if ref.is_a?(Integer) || ref.to_s.match?(/\A\d+\z/)

        id = written_id(resource, ref)
        return by_id(resource, id) if id

        id_on_date(resource, ref) || (ref.blank? ? latest(resource) : by_words(resource, ref.to_s))
      end

      # The records the user was shown, exactly (Operations::Base#pin), in
      # order: a saved one by id, a series' day that had no row by its series,
      # date and time, the day still on its calendar. Never searched for
      # again; nil in place of one that went, or the user can no longer reach.
      def pinned(type, pins)
        resource = Resources.fetch(type)
        saved = resource.where_accessible(@profile, pins.filter_map { |pin| pin["id"] }).index_by(&:id)
        days = pins.reject { |pin| pin["id"] }
        series = {}
        if days.any?
          dates = days.map { |pin| Date.iso8601(pin["date"]) }
          found = Event.accessible_by(@profile).of_type(resource.type).where(id: days.map { |pin| pin["event_id"] }).to_a
          series = Event.preload_occurrences(found, dates.min, dates.max).index_by(&:id)
        end
        pins.map do |pin|
          next saved[pin["id"].to_i] if pin["id"]

          date = Date.iso8601(pin["date"])
          series[pin["event_id"].to_i]&.occurrences_between(date, date)&.find { |day| day.time_string == pin["time"] }
        end
      end

      private

      # "… at 20:00" / "… alle 8" / "… at dinner": the dose of the day, as
      # "HH:MM", and the ref without it.
      def split_time(ref)
        said = ref.match(TIME_SUFFIX)
        code = Events::TimesOfDay.code_for(said[:time]) if said
        code ? [ said.pre_match, Events::TimesOfDay.hhmm(code) ] : [ ref, nil ]
      end

      # How models write an id: "#109", "id 109", "lab_test_result:109",
      # "lab result 109". Only the type's own words may come before the
      # number, so "Calcium: 300" stays words.
      def written_id(resource, ref)
        written = ref.to_s.strip.downcase.match(/\A(?<prefix>[a-z_ ]*?)[\s:#=]*(?<id>\d+)\z/)
        return unless written

        type_words = resource.key.split("_") + Resources::ALIASES.select { |_, key| key == resource.key }.keys.flat_map { |k| k.split("_") } + %w[id record]
        written[:id] if written[:prefix].split(/[\s_]+/).all? { |word| type_words.include?(word) }
      end

      def by_id(resource, id)
        Resolution.found(at_time(resource.find_accessible(@profile, id.to_i)))
      rescue ActiveRecord::RecordNotFound
        series = series(resource, id)
        return Resolution.missing("no #{resource.key} with id #{id} — search for it first") unless series

        on_day(series, Date.current) || next_one(series) ||
          Resolution.missing("#{id} is a repeating #{resource.key}'s event_id, and it isn't due today — say which day (ref \"event_id #{id} on YYYY-MM-DD\")")
      end

      # "event_id 42 on 2026-09-24", "42, date 2026-09-24", "#42 yesterday":
      # a record with that id on that day, or that series' day. With
      # "event_id" or "series" written, the number is the series', never a
      # record that happens to have the same id. Nil when the ref is not
      # written that way.
      def id_on_date(resource, ref)
        written = ref.to_s.strip.match(ID_ON_DATE)
        return unless written

        id = written[:id]
        series_named = written[:prefix].to_s.downcase.match?(/event|series/)
        return unless written[:day] || series_named

        day = written[:day] ? DateWords.parse(written[:day]) : Date.current
        return unless day

        record = resource.accessible(@profile).find_by(id: id) unless series_named
        return by_id(resource, record.id) if record && (!resource.eventable? || record.date == day)

        series = series(resource, id)
        return Resolution.missing("no #{resource.key} or series with id #{id} — search for it first") unless series

        on_day(series, day) || (next_one(series) unless written[:day]) ||
          Resolution.missing("the #{resource.key} series #{id} has nothing on #{day.iso8601}#{" — say which day (ref \"event_id #{id} on YYYY-MM-DD\")" unless written[:day]}")
      end

      def series(resource, id)
        return unless resource.eventable?

        Event.accessible_by(@profile).of_type(resource.type).find_by(id: id)
      end

      # The series' next day from today, for a change to what it does from
      # now on (upcoming).
      def next_one(event)
        return unless @upcoming

        day = event.occurrence_dates_between(Date.current, Date.current + Resources::CalendarResource::NEXT_DAY_WITHIN).first
        on_day(event, day) if day
      end

      # The series' day: scheduled (saved or projected), else one saved off
      # its schedule (a day moved there, a dose at an extra time).
      def on_day(event, day)
        time = (@time if event.timed?)
        record = if event.occurrence_dates_between(day, day).include?(day)
          event.occurrence_for(day, time: time)
        else
          saved = event.occurrences.where(date: day).in_order.to_a
          time ? saved.find { |occurrence| occurrence.time_string == time } : (saved.find(&:pending?) || saved.last)
        end
        Resolution.found(record) if record
      end

      # No ref: what this chat last worked on, the one in use, or the most
      # recent record, the user's own before a linked housemate's ("the last
      # task" isn't theirs).
      def latest(resource)
        own = chat_records(resource).first
        return Resolution.found(own) if own
        return in_use(resource) if resource.in_use?

        recent = resource.dated_within(@profile, (Date.current - RECENT)..Date.current)
        record = (recent.where(event_id: Event.where(profile_id: @profile.id).select(:id)).first if resource.eventable?) || recent.first
        record ? Resolution.found(record, assumed: true) : Resolution.missing("no recent #{resource.key} found — say which one")
      end

      def by_words(resource, text)
        date, rest = self.class.split_date(text)
        words = rest.downcase.scan(/[[:alnum:]]{2,}/) - STOPWORDS
        found = search(resource, words, date, date) if date
        found = search(resource, words, date - 3, date + 3) if date && found.empty?
        found = search(resource, words, nil, nil) if found.nil? || (found.empty? && words.any?)
        found = one_dose(found)
        found = chat_choice(resource, found, words)
        if resource.in_use?
          found = in_use_among(resource, found)
          # "la lista della spesa", with no list called that: the one in use.
          return in_use(resource) if found.empty? && words.all? { resource.kind_word?(_1) }
        end
        case found.size
        when 1 then Resolution.found(record_for(resource, found.first))
        when 0 then Resolution.missing("no #{resource.key} matches #{text.inspect}")
        else Resolution.ambiguous(found.first(5), "several #{resource.key.pluralize} match #{text.inspect}; ask which one")
        end
      end

      # A kind with records in use (grocery lists): the one in use, or the
      # names to ask between; none in use is said, so the model starts one.
      def in_use(resource)
        records = resource.in_use(@profile).limit(6).to_a
        case records.size
        when 1 then Resolution.found(records.first)
        when 0 then Resolution.missing("no #{resource.key} in use: start one")
        else Resolution.ambiguous(records.first(5).map { resource.summarize(_1, profile: @profile) },
                                  "several #{resource.key.pluralize} are in use; ask which one")
        end
      end

      # Among several matches, the ones in use, when any are.
      def in_use_among(resource, found)
        return found unless found.many?

        ids = resource.in_use(@profile).ids
        current = found.select { |summary| ids.include?(summary[:id]) }
        current.any? ? current : found
      end

      # Among several matches, the one this chat worked on; with nothing
      # matched and no words beyond the type and a date, the latest one it
      # worked on. Otherwise the matches as they are.
      def chat_choice(resource, found, words)
        own = chat_records(resource)
        return found if own.empty? || found.one?

        if found.empty?
          words.empty? ? [ { id: own.first.id } ] : found
        else
          ids = own.map(&:id)
          mine = found.select { |summary| ids.include?(summary[:id]) }
          mine.one? ? mine : found
        end
      end

      # This chat's records of the type, from its applied change sets' undo
      # logs (saved, changed, marked done), most recent first.
      def chat_records(resource)
        return [] unless @chat

        @chat_touched ||= ChangeSet.where(chat: @chat, status: :applied).order(applied_at: :desc, id: :desc).limit(CHAT_CHANGE_SETS)
          .flat_map { |set| Array(set.undo_log).reverse }
          .filter_map { |entry| [ entry["model"], entry["id"] ] if entry.is_a?(Hash) && entry["kind"].in?(%w[created updated status]) }.uniq
        ids = @chat_touched.filter_map { |model, id| id if model == resource.model.name }
        records = resource.accessible(@profile).where(id: ids).index_by(&:id)
        ids.filter_map { |id| records[id] }
      end

      # Several doses of one day: the one at the time asked for, else the
      # first still to take (the last when all are done). "I took my
      # metformin" is one dose, not a question, and it is the next one, not
      # the dose this chat just marked, which is why this runs before
      # chat_choice.
      def one_dose(found)
        return found unless found.size > 1 && found.all? { |f| f[:event_id] && f[:time] } && found.map { |f| [ f[:event_id], f[:date] ] }.uniq.one?

        ordered = found.sort_by { |f| f[:time].to_s }
        at = ordered.find { |f| f[:time] == @time } if @time
        [ at || ordered.find { |f| f[:status] == "pending" } || ordered.last ]
      end

      # A saved record, or an upcoming day of a series built unsaved; with a
      # time asked for, that dose of the record's day.
      def record_for(resource, found)
        return at_time(resource.find_accessible(@profile, found[:id])) if found[:id]

        event = Event.accessible_by(@profile).find(found[:event_id])
        event.occurrence_for(Date.iso8601(found[:date]), time: (@time || found[:time] if event.timed?))
      end

      # With a time asked for ("… at 20:00"), that dose of the record's day.
      def at_time(record)
        return record unless @time && record.try(:event)&.timed? && record.time_string != @time

        record.event.occurrence_for(record.date, time: @time)
      end

      def search(resource, words, from, to)
        resource.search(@profile, query: words.join(" ").presence, date_from: from, date_to: to)
      end
    end
  end
end
