# frozen_string_literal: true

# Turns the words people use for a day into a date, so the model can pass
# the user's own phrase ("a week ago", "last Friday", "venerdì prossimo")
# instead of doing date arithmetic, which small models get wrong. ISO dates
# pass through.
#
#   Assistant::DateWords.parse("a week ago", today: Date.new(2026, 9, 23))  # => 2026-09-16
module Assistant
  module DateWords
    WEEKDAYS = {
      "monday" => 1, "tuesday" => 2, "wednesday" => 3, "thursday" => 4, "friday" => 5, "saturday" => 6, "sunday" => 0,
      "lunedì" => 1, "lunedi" => 1, "martedì" => 2, "martedi" => 2, "mercoledì" => 3, "mercoledi" => 3,
      "giovedì" => 4, "giovedi" => 4, "venerdì" => 5, "venerdi" => 5, "sabato" => 6, "domenica" => 0
    }.freeze
    NUMBERS = { "a" => 1, "an" => 1, "one" => 1, "un" => 1, "una" => 1, "uno" => 1, "two" => 2, "due" => 2,
                "three" => 3, "tre" => 3, "four" => 4, "quattro" => 4, "few" => 3, "couple" => 2 }.freeze
    MONTHS = {
      "january" => 1, "february" => 2, "march" => 3, "april" => 4, "may" => 5, "june" => 6, "july" => 7,
      "august" => 8, "september" => 9, "october" => 10, "november" => 11, "december" => 12,
      "jan" => 1, "feb" => 2, "mar" => 3, "apr" => 4, "jun" => 6, "jul" => 7, "aug" => 8, "sep" => 9, "sept" => 9,
      "oct" => 10, "nov" => 11, "dec" => 12,
      "gennaio" => 1, "febbraio" => 2, "marzo" => 3, "aprile" => 4, "maggio" => 5, "giugno" => 6, "luglio" => 7,
      "agosto" => 8, "settembre" => 9, "ottobre" => 10, "novembre" => 11, "dicembre" => 12
    }.freeze
    UNITS = { "day" => 1, "days" => 1, "giorno" => 1, "giorni" => 1, "week" => 7, "weeks" => 7,
              "settimana" => 7, "settimane" => 7 }.freeze

    module_function

    def parse(text, today: Date.current)
      # "today's" and "Friday," are read as "today" and "friday".
      phrase = text.to_s.downcase.gsub(/['’]s\b/, "").gsub(/[?!.,;:]/, " ").squish.delete_prefix("about ").delete_prefix("circa ")
      return if phrase.empty?

      iso(phrase) || fixed(phrase, today) || relative(phrase, today) || weekday(phrase, today) || calendar(phrase, today)
    end

    # "September 25, 2026", "25 September", "on the 25th of Sept", "25 settembre 2026".
    # Without a year: this year's.
    def calendar(phrase, today)
      words = phrase.split - %w[on the of il del di]
      month = words.find { |w| MONTHS.key?(w) }
      rest = words - [ month ]
      day = rest.find { |w| w.match?(/\A\d{1,2}(st|nd|rd|th)?\z/) }
      return unless month && day

      year = rest.find { |w| w.match?(/\A\d{4}\z/) }
      return unless (rest - [ day, year ].compact).empty?

      Date.new(year&.to_i || today.year, MONTHS.fetch(month), day.to_i)
    rescue Date::Error
      nil
    end

    def iso(phrase)
      Date.iso8601(phrase[/\A\d{4}-\d{2}-\d{2}/].to_s)
    rescue Date::Error
      nil
    end

    def fixed(phrase, today)
      case phrase
      when "today", "oggi" then today
      when "yesterday", "ieri" then today - 1
      when "tomorrow", "domani" then today + 1
      when "the day before yesterday", "l'altro ieri", "altro ieri" then today - 2
      when "last week", "la settimana scorsa", "settimana scorsa" then today - 7
      when "last month", "il mese scorso", "mese scorso", "a month ago", "un mese fa" then today.prev_month
      when "next week", "la settimana prossima", "settimana prossima" then today + 7
      end
    end

    # "a week ago", "3 days ago", "tra 2 settimane", "in 3 days", "2 giorni fa"
    def relative(phrase, today)
      m = phrase.match(/\A(?:in |tra |fra )?(\d+|#{NUMBERS.keys.join("|")})\s+(?:of\s+)?(#{UNITS.keys.join("|")})(?:\s+(ago|fa))?\z/o)
      return unless m && (m[3] || phrase.match?(/\A(in|tra|fra) /))

      count = m[1].match?(/\d/) ? m[1].to_i : NUMBERS.fetch(m[1])
      days = count * UNITS.fetch(m[2])
      m[3] ? today - days : today + days
    end

    # "last friday" / "venerdì scorso" (the most recent one before today),
    # "this friday" / "friday" / "venerdì" (the next one, today excluded),
    # "next friday" / "venerdì prossimo" (a week after "this friday").
    def weekday(phrase, today)
      words = phrase.split
      day = words.find { |w| WEEKDAYS.key?(w) }
      return unless day

      wday = WEEKDAYS.fetch(day)
      upcoming = (1..7).map { |n| today + n }.find { |d| d.wday == wday }

      if (words & %w[last scorso scorsa]).any? then upcoming - 7
      elsif (words & %w[next prossimo prossima]).any? then upcoming + 7
      elsif words.size == 1 || (words & %w[this questo questa on]).any? then upcoming
      end
    end
  end
end
