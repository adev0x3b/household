# frozen_string_literal: true

# Gives a series a new repeat, and new times of the day, from now on. A
# series with days behind it is never rewritten from its start: the days a
# new rule would project into its past were never planned, and the days
# that were planned and done would be off its schedule. It is ended the
# day before the change instead and goes on as a new series under the new
# rule, which takes over its shares and reminders (Event#continuation).
# A series whose days are all ahead, or whose repeat and times stay as
# they are, takes the change in place; a one-off staying a one-off too,
# since its day is the series.
#
# The change goes on from today, or from the day after the series' last
# done day when that is today or later: a dose taken this morning is on
# the record, and the new times start tomorrow rather than beside it.
# Taking the repeat away from a series with a past stops it there, rather
# than leaving only its first day and losing what was missed.
#
#   result = Events::Reschedule.call(event, rrule: "FREQ=WEEKLY;BYDAY=TU", slots: %w[08:00])
#   result.series   # the series under the new rule: the event itself, or the continuation that took over
#   result.error    # :never_happens when the new rule has no day to come, in which case nothing changed
#
# `slots` nil leaves the times as they are. Whoever calls has authorized
# the change to the series: the continuation is that change, not a new
# series of the caller's, so none is asked for it.
module Events
  class Reschedule
    Result = ServiceResult.define(:series)

    def self.call(event, rrule:, slots: nil) = new(event, rrule: rrule, slots: slots).call

    def initialize(event, rrule:, slots:)
      @event = event
      @rrule = rrule.presence
      @slots = slots
    end

    def call
      return Result.new(series: rewrite!, error: nil) if rewrite_in_place?
      return Result.new(series: stop!, error: nil) if @rrule.nil?

      first = Events::Schedule.new(@event.starts_on, @rrule).first_date_from(from)
      return Result.new(series: @event, error: :never_happens) unless first

      Result.new(series: continue_from!(first), error: nil)
    end

    private

    def rewrite_in_place?
      !@event.past_days? || (!pattern_changed? && !slots_changed?) || (!@event.recurring? && @rrule.nil?)
    end

    def pattern_changed? = Events::RecurrenceRule.pattern(@rrule) != Events::RecurrenceRule.pattern(@event.rrule)
    def slots_changed? = !@slots.nil? && @event.slots_differ_from?(@slots)

    # The first day the change applies to.
    def from
      last_done = @event.occurrences.completed.maximum(:date)
      [ Date.current, last_done&.next_day ].compact.max
    end

    # The rule first: writing the slots saves them at once, and the series'
    # row is then saved with its rule rather than once more.
    def rewrite!
      @event.update!(rrule: @rrule)
      @event.assign_slots(@slots) unless @slots.nil?
      @event
    end

    def stop!
      end_on!(from.prev_day)
      @event
    end

    def continue_from!(first)
      continuation = @event.continuation(starts_on: first)
      continuation.rrule = @rrule
      continuation.assign_slots(@slots) unless @slots.nil?
      continuation.save!
      end_on!(from.prev_day)
      @event.hand_over_audience_to!(continuation)
      continuation
    end

    # The series under its own pattern up to `date`, or up to the end it
    # already had when that came first.
    def end_on!(date)
      fields = Events::RecurrenceRule.describe(@event.rrule)
      ends = [ fields[:ends], date ].compact.min
      @event.update!(rrule: Events::RecurrenceRule.build(**fields.slice(:frequency, :interval, :week_days), ends: ends))
    end
  end
end
