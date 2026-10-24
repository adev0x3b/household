# frozen_string_literal: true

# Deletes a day of a series, or the whole series — or many days at once
# (the assistant deleting what matched), a series at a time.
#
#   Occurrences::Destroy.call(day, by: current_profile, scope: :occurrence)   # => :occurrence or :series, what went
#   Occurrences::Destroy.call(days, by: current_profile, scope: :series)
#
# * scope :occurrence on a recurring series — the days' rows go, and the
#   days (their slots of the day, for a series taken several times a day)
#   are excluded so the series doesn't project them again. What a linked
#   housemate asked about those days is cancelled.
# * scope :series, or any one-off — every stored day and the series itself.
#
# What a kind gives back runs first (Event#on_occurrences_destroying); then
# rows go in bulk (Occurrence.delete_with_children, Events::Purge), so many
# days cost what one does. Authorized with each day's policy `destroy?`;
# broadcasts after commit: one series' cards, or — many series at once —
# a refresh of everyone's calendars who saw them.
module Occurrences
  class Destroy
    SCOPES = %w[occurrence series].freeze

    def self.call(days, **) = new(days, **).call

    # `days`: one day, or many of any number of series.
    def initialize(days, by:, scope: "occurrence")
      raise ArgumentError, "unknown scope #{scope.inspect}" unless SCOPES.include?(scope.to_s)

      @days = Array.wrap(days)
      @profile = by
      @scope = scope.to_s
    end

    def call
      @days.each { |day| Pundit.authorize(@profile, day, :destroy?) }
      series = @days.group_by(&:event_id).values.map { |days| [ days.first.event, days ] }
      audience = series.one? ? series.first.first.audience : Event.audience_of(series.map(&:first))
      whole, partly = series.partition { |event, _| whole?(event) }

      ActiveRecord::Base.transaction do
        remove_series(whole.map(&:first)) if whole.any?
        partly.each { |event, days| remove_days(event, days) }
      end

      broadcast(series, audience)
      whole?(series.first.first) ? :series : :occurrence
    end

    private

    def whole?(event) = @scope == "series" || !event.recurring?

    # Every stored day of each series gives back what it did, what was asked
    # about them is cancelled, and they go.
    def remove_series(events)
      saved = Occurrence.where(event_id: events.map(&:id)).includes(:event).group_by(&:event_id)
      events.each { |event| event.on_occurrences_destroying(saved.fetch(event.id, [])) }
      cancel_requests(events)
      Events::Purge.call(events)
    end

    def remove_days(event, days)
      event.on_occurrences_destroying(days)
      cancel_requests_about(event, days)
      Occurrence.delete_with_children(days.select(&:persisted?))
      event.skip_all!(days.map { |day| [ day.date, day.time_string ] })
    end

    def broadcast(series, audience)
      if series.one?
        event, days = series.first
        Calendar::DayCardBroadcaster.call(event: event, dates: days.map(&:date).uniq, extra_profiles: audience)
      else
        Calendar::Refresh.call(*audience)
      end
    end

    # What a linked housemate asked about the series can't be done anymore.
    def cancel_requests(events)
      cancel(LinkApproval.pending.where(event_id: events.map(&:id)).ids)
    end

    # Nor what they asked about the days that go: a dose, or any dose of a
    # day removed whole. A request to delete the whole series still can be.
    def cancel_requests_about(event, days)
      gone = days.map(&:key)
      whole_days = gone.filter_map { |date, time| date if time.nil? }
      saved = days.filter_map(&:id)
      about_them = LinkApproval.pending.where(event_id: event.id).select do |request|
        next false if request.scope == "series"

        saved.include?(request.occurrence_id) || whole_days.include?(request.date) || gone.include?([ request.date, request.time_string ])
      end
      cancel(about_them.map(&:id))
    end

    # Cancelled, and settled as a decision is once it commits: the owner's
    # bell row loses its Approve, both Links pages their line.
    def cancel(ids)
      return if ids.empty?

      LinkApproval.where(id: ids).update_all(status: LinkApproval.statuses[:cancelled], decided_at: Time.current)
      ActiveRecord.after_all_transactions_commit do
        LinkApproval.where(id: ids).find_each { |request| Links::Approvals::Decide.settled(request) }
      end
    end
  end
end
