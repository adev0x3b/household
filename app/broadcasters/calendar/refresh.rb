# frozen_string_literal: true

module Calendar
  # Reloads the months these people have open on the calendar (a Turbo `refresh`
  # over their calendar rooms, per CalendarWatch): for when many of their day
  # cards change at once — a link made or ended, a type of the partner's
  # items shown or hidden — where re-rendering card by card would be
  # hundreds of broadcasts.
  class Refresh < ApplicationBroadcaster
    def self.call(*profiles)
      quietly do
        refresh = ApplicationController.helpers.turbo_stream_refresh_tag
        CalendarWatch.months_by_profile(profiles.map(&:id)).each do |profile_id, year_months|
          year_months.each { |year_month| ActionCable.server.broadcast("profile_#{profile_id}:#{year_month}", refresh) }
        end
      end
    end
  end
end
