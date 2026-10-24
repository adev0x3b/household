# frozen_string_literal: true

module Demo
  # One side of the demo household's life (chores, money, health, the
  # kitchen), lived a day at a time. Demo::Seeder calls #day for every date
  # of the six months, with the clock set to it, then #finish on the last.
  #
  # A part says what happens when, and never writes history directly:
  #
  #   at(date) { … }    something done on that date (now, if it has come;
  #                     never, if it's after today — which is how upcoming
  #                     things stay open)
  #   create(…)         a new series on someone's calendar, saved the way
  #                     its form saves it (Occurrences::Create); its days
  #                     are reached through it (#occurrence, first_occurrence)
  #   follow(series)    a series whose days each get an outcome on their
  #                     day: done, done a day or two late, skipped, or left
  #                     alone (so the app sees it as missed) — each dose of a
  #                     day on its own, for a medication taken at set times
  #   daily(day)        whatever the part does every day
  class Part
    # A followed series. `done` is the share of days that get done: a
    # number, or [ at the start, today ] for a habit that changed. `force`
    # fixes the outcome of given dates (or of one dose: [ date, "HH:MM" ]);
    # `before` and `after` are called with the day (an Occurrence) around its
    # completion. `rng` is a series' own Random (`apart: true`): one added
    # later draws from it, so the stories already told keep their every roll.
    Followed = Struct.new(:event, :done, :skipped, :late, :early, :force, :before, :after, :rng, keyword_init: true)
    # Why a dose was skipped, when it was (Occurrence#skipped_reason, for the
    # kinds that know reasons: a medication's).
    SKIP_REASONS = %w[forgot forgot not_available other].freeze

    delegate :today, :start, :rng, :chance?, :pick, :amount, :progress, :share, :alex, :sam, :robin, to: :@world

    def initialize(world)
      @world = world
      @agenda = Hash.new { |agenda, date| agenda[date] = [] }
      @followed = []
    end

    def day(day)
      @now = day
      setup if day == start
      run(@agenda.delete(day)) while @agenda.key?(day)
      daily(day)
      settle(day)
    end

    # What only makes sense once the past is in place: the days ahead.
    def finish; end

    private

    def setup; end
    def daily(_day); end

    def run(blocks) = blocks.each(&:call)

    def at(date, &block)
      date <= @now ? yield : @agenda[date] << block
    end

    # `days` before today (after it, when negative).
    def ago(days) = today - days

    # Never in the future: what's upcoming was still entered by today.
    def entered(date, lead) = [ date - lead, today ].min

    # Saves a built series (an Event subclass with its details) on
    # `profile`'s calendar, repeating as `recurrence` says (frequency,
    # interval, week_days, ends, slots), in `collection`; returns the series.
    def create(profile, event, recurrence: nil, collection: nil)
      Occurrences::Create.call(event, by: profile, recurrence: recurrence, collection_id: collection&.id)
    end

    # Who wants to hear about a series, and how long before: remind(task, alex, [ 1, "days" ], [ 3, "hours" ]).
    def remind(event, profile, *offsets)
      Events::SetReminders.call(event, profile: profile, entries: offsets.map { |amount, unit| { amount: amount, unit: unit } })
    end

    def follow(event, done: 0.9, skipped: 0.03, late: 0.1, early: 0, force: {}, before: nil, after: nil, apart: false)
      @followed << Followed.new(event: event, done: done, skipped: skipped, late: late, early: early,
                                force: force, before: before, after: after, rng: (Random.new(event.starts_on.jd) if apart))
      event
    end

    def rolls(followed) = followed.rng || rng

    def settle(day)
      @followed.each do |followed|
        followed.event.occurrences_between(day, day).each { |dose| settle_occurrence(followed, day, dose.time_string) }
        next unless day < today && followed.early.positive? && chance?(followed.early)

        followed.event.occurrences_between(day + 1, day + 1).each { |dose| complete(followed, day + 1, dose.time_string) }
      end
    end

    def settle_occurrence(followed, day, time)
      return unless occurrence(followed.event, day, time).pending? # done the day before

      case followed.force[[ day, time ]] || followed.force[day] || draw(followed, day)
      when :done then complete(followed, day, time, at: taken_at(followed, day, time))
      when :late then at(day + rolls(followed).rand(1..2)) { complete(followed, day, time) }
      when :skipped then skip(followed, day, time)
      when :cancelled then occurrence(followed.event, day, time).change_status!("cancelled")
      end
    end

    def skip(followed, day, time)
      record = occurrence(followed.event, day, time)
      reason = SKIP_REASONS[rolls(followed).rand(SKIP_REASONS.size)] if record.event.class.skip_reasons.any?
      record.change_status!("skipped", reason: reason)
    end

    # When a dose at a set time was taken: around its time (the clock
    # otherwise sits at noon all day, see Demo::Seeder#on).
    def taken_at(followed, day, time)
      return Time.current unless time

      hour, minute = Events::TimesOfDay.clock(time)
      Time.zone.local(day.year, day.month, day.day, hour, minute) + rolls(followed).rand(-10..25).minutes
    end

    def draw(followed, day)
      done = followed.done.is_a?(Array) ? followed.done.first + ((followed.done.last - followed.done.first) * progress(day)) : followed.done
      roll = rolls(followed).rand
      if roll < done then rolls(followed).rand < followed.late ? :late : :done
      elsif roll < done + followed.skipped then :skipped
      else :missed
      end
    end

    def complete(followed, day, time = nil, at: Time.current)
      record = occurrence(followed.event, day, time)
      return record unless record.pending?

      followed.before&.call(record)
      record.complete!(at: at)
      followed.after&.call(record)
      record
    end

    # The day of a series — the dose at `time` ("HH:MM"), for a series taken
    # several times a day — saved, or a projected one to act on.
    def occurrence(event, day, time = nil) = event.occurrence_for(day, time: time)

    # The cost of something (a visit's fee, a meal out, a purchase), as its
    # forms attach it (Transactions::SetCost); returns the cost's day.
    def pay(about, amount, on:, title: cost_title(about), to: nil, category: :healthcare, method: "card", status: :completed)
      Transactions::SetCost.call(about, date: on, title: title, amount: amount, payment_method: method,
                                        status: status, category: category, counterpart: to).cost
    end

    # What a cost is called: a day by its series (Appointment#cost_title,
    # Meal#cost_title), a purchase by itself.
    def cost_title(about) = about.is_a?(Occurrence) ? about.event.cost_title(about) : about.cost_title

    # The first `weekday` (:monday…) on or after `date`.
    def next_weekday(date, weekday)
      date + ((Date::DAYNAMES.index(weekday.to_s.capitalize) - date.wday) % 7)
    end

    # The first date on or after `date` that is the `day_of_month`th.
    def next_month_day(date, day_of_month)
      candidate = date.change(day: day_of_month)
      candidate >= date ? candidate : candidate.next_month
    end
  end
end
