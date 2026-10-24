# frozen_string_literal: true

module Events
  # The doses of a day, as FHIR's Timing writes them: a list of clock times
  # ("08:00") or of anchors from the EventTiming value set — CM with
  # breakfast, CD with lunch, CV with dinner, HS at bedtime — that resolve
  # to the household's usual hours. Stored as EventSlot rows; an empty
  # list is one untimed dose a day (Event#event_slots).
  #
  #   Events::TimesOfDay.expand(%w[CV 08:00]) # => [ [ "08:00", nil ], [ "19:30", "CV" ] ]
  #   Events::TimesOfDay.code_for("dinner")   # => "CV"
  module TimesOfDay
    MORNING = [ 9, 0 ].freeze
    MEALS = { "breakfast" => [ 8, 0 ], "lunch" => [ 12, 30 ], "snack" => [ 16, 0 ], "dinner" => [ 19, 30 ] }.freeze
    ANCHORS = { "CM" => MEALS["breakfast"], "CD" => MEALS["lunch"], "CV" => MEALS["dinner"], "HS" => [ 22, 0 ] }.freeze
    MAX_PER_DAY = 6

    # ISMP's standard administration times per number of doses a day.
    DEFAULTS = {
      1 => %w[08:00],
      2 => %w[08:00 20:00],
      3 => %w[08:00 14:00 20:00],
      4 => %w[08:00 12:00 16:00 20:00],
      5 => %w[08:00 11:30 15:00 18:30 22:00],
      6 => %w[06:00 09:00 12:00 15:00 18:00 21:00]
    }.freeze

    # How people (and the assistant) say an anchor, in the app's languages.
    WORDS = {
      "CM" => %w[breakfast morning colazione mattina],
      "CD" => %w[lunch noon midday pranzo mezzogiorno],
      "CV" => %w[dinner evening supper cena sera],
      "HS" => %w[bedtime night bed letto notte]
    }.freeze

    CLOCK = /\A([01]\d|2[0-3]):[0-5]\d\z/

    # How the assistant says an anchor ("breakfast"); nil for a clock time.
    def self.word(code) = WORDS.dig(code.to_s, 0)

    # A slot as the page reads it: "with breakfast", or "08:00" in the locale.
    def self.time_label_for(time, anchor)
      return I18n.t("medications.anchors.#{anchor}") if anchor.present?
      return nil if time.blank?

      hour, minute = clock(time)
      I18n.l(Time.utc(2000, 1, 1, hour, minute), format: :hour_minute)
    end

    # "with breakfast" / "at 08:00".
    def self.when_label_for(time, anchor)
      return I18n.t("medications.anchors.#{anchor}") if anchor.present?

      (label = time_label_for(time, nil)) && I18n.t("medications.at_time", time: label)
    end

    def self.anchor?(entry) = ANCHORS.key?(entry.to_s)
    def self.valid?(entry) = anchor?(entry) || CLOCK.match?(entry.to_s)

    # [hour, minute] of an entry.
    def self.clock(entry)
      anchor?(entry) ? ANCHORS.fetch(entry.to_s) : entry.to_s.split(":").map(&:to_i)
    end

    # "HH:MM" of an entry.
    def self.hhmm(entry) = format("%02d:%02d", *clock(entry))

    # Each entry as [ "HH:MM", anchor or nil ], by the clock, one per time.
    def self.expand(list)
      Array(list).select { |entry| valid?(entry) }
        .map { |entry| [ hhmm(entry), (entry.to_s if anchor?(entry)) ] }
        .uniq(&:first).sort_by(&:first)
    end

    # What gets saved: valid entries, stripped, uniq, in clock order.
    def self.normalize(list)
      Array(list).map { |entry| entry.to_s.strip.upcase }.select { |entry| valid?(entry) }
        .uniq { |entry| hhmm(entry) }.sort_by { |entry| hhmm(entry) }
    end

    # An anchor code or "HH:MM" from how someone wrote it ("dinner", "8pm",
    # "20:00", "CV"), or nil when it can't be read.
    def self.code_for(word)
      text = word.to_s.strip
      return nil if text.blank?
      return text.upcase if anchor?(text.upcase)
      return text if CLOCK.match?(text)

      WORDS.each { |code, words| return code if words.include?(text.downcase.delete_suffix("time").strip) || words.include?(text.downcase) }
      parse_clock(text)
    end

    # "8", "8:30", "8pm", "8.30 pm", "20h" → "HH:MM".
    def self.parse_clock(text)
      m = text.downcase.match(/\A(\d{1,2})(?:[:.h](\d{2})|h)?\s*(am|pm)?\z/) or return nil
      hour, minute = m[1].to_i, m[2].to_i
      hour += 12 if m[3] == "pm" && hour < 12
      hour = 0 if m[3] == "am" && hour == 12
      return nil if hour > 23 || minute > 59

      format("%02d:%02d", hour, minute)
    end
    private_class_method :parse_clock
  end
end
