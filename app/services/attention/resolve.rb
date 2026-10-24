# frozen_string_literal: true

# Marks every day of a series that has passed and is still to do as
# skipped, so the series leaves "Needs attention" without pretending
# anything was done: a dose nobody took stays untaken, on the record as
# skipped. Takes one series or many (the page's whole list).
#
#   Attention::Resolve.call(series, by: current_profile)   # => the days now skipped
#
# Each day is checked with its own policy, whoever calls. A day a linked
# housemate may only ask about is left as it is: the press promised to
# settle the list, not to send the owner a request.
module Attention
  class Resolve
    def self.call(series, **) = new(series, **).call

    def initialize(series, by:, today: Date.current)
      @series = Array.wrap(series)
      @profile = by
      @today = today
    end

    def call
      days = unfinished_days.select { |day| allowed?(day) }
      Costable.preload_costs(days)
      ActiveRecord::Base.transaction { days.each { |day| day.edited_by(@profile).change_status!("skipped") } }
      broadcast(days)
      days
    end

    private

    # One series' cards are redrawn where they are shown; many series at
    # once refresh the calendars of everyone who saw any of them, as
    # deleting many does.
    def broadcast(days)
      series = days.map(&:event).uniq
      return if series.empty?

      if series.one?
        Calendar::DayCardBroadcaster.call(event: series.first, dates: days.map(&:date).uniq)
      else
        Calendar::Refresh.call(*Event.audience_of(series))
      end
    end

    # The same days the list showed, read as the list reads them, of these
    # series alone.
    def unfinished_days
      return [] if @series.empty?

      ids = @series.map(&:id)
      unfinished = Reports::Unfinished.new(Reports::Audience.new(viewer: @profile), today: @today)
      unfinished.entries(of: @series.map(&:class).uniq) { |event| ids.include?(event.id) }.map(&:occurrence)
    end

    def allowed?(day)
      policy = Pundit.policy!(@profile, day)
      policy.change_status? && !policy.needs_approval?(:change_status?)
    end
  end
end
