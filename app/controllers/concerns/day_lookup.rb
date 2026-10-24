# frozen_string_literal: true

# The series and the day a route under /events/:event_id/days/:date names:
# the series among those the viewer may read, and its day on that date,
# saved or projected. `time` picks the dose of a series taken several times
# a day; without it the day's dose still to take is meant.
module DayLookup
  extend ActiveSupport::Concern

  private

  def event
    @event ||= Event.accessible_by(current_profile).includes(:event_shares, collection: :collection_shares).find(params[:event_id])
  end

  def day
    @day ||= event.occurrence_for(requested_date, time: params[:time].presence)
  end

  # A date that isn't one is a day that doesn't exist.
  def requested_date
    Date.iso8601(params[:date].to_s)
  rescue Date::Error
    raise ActiveRecord::RecordNotFound, "no such day: #{params[:date].inspect}"
  end
end
