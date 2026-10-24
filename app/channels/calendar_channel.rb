# frozen_string_literal: true

# Month-year scoped calendar channel for real-time day card updates.
#
# Clients subscribe with a `room` param formatted as:
#   "profile_<id>:<YYYY>-<MM>"
# and may only subscribe to rooms of their own profile (the connection is
# authenticated — see ApplicationCable::Connection).
#
# While subscribed, the room is a CalendarWatch row, refreshed every
# CalendarWatch::REFRESH_EVERY, so every process knows which months each
# profile has open and the broadcasters skip rendering the others.
#
# Subscribe (JS):
#   consumer.subscriptions.create(
#     { channel: "CalendarChannel", room: "profile_1:2026-03" },
#     { received(data) { Turbo.renderStreamMessage(data) } }
#   )
class CalendarChannel < ApplicationCable::Channel
  ROOM_FORMAT = /\Aprofile_(\d+):\d{4}-\d{2}\z/

  periodically :keep_watching, every: CalendarWatch::REFRESH_EVERY

  def subscribed
    if own_room?
      stream_from params[:room]
      CalendarWatch.sweep!
      keep_watching
    else
      reject
    end
  end

  def unsubscribed
    CalendarWatch.unwatch!(watch_id)
  end

  private

  def keep_watching
    CalendarWatch.watch!(params[:room], watch_id) if own_room?
  end

  # This subscription's own row: another tab on the same month has its own.
  def watch_id = @watch_id ||= SecureRandom.uuid

  # A profile may only listen to its own calendar rooms.
  def own_room?
    params[:room].to_s.match(ROOM_FORMAT)&.captures&.first == current_profile.id.to_s
  end
end
