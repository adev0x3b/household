# frozen_string_literal: true

# Whether a day of a series is done, from the circle on its card: the press
# says which state it wants (a POST marks the day done, a DELETE not done)
# rather than "the other one", so a second tap, a housemate's tap or a page
# that was out of date leaves the day as asked. A day nothing was stored
# about yet gets its row as it is marked done. A linked housemate's tap is
# held for the owner's OK where their grant says to ask (LinkApprovable).
class DayCompletionsController < ApplicationController
  include DayLookup
  include LinkApprovable

  def create = mark(true)
  def destroy = mark(false)

  private

  def mark(completed)
    authorize day, :change_status?
    return if held_for_approval?(day, :change_status?, kind: completed ? :complete : :uncomplete)

    day.edited_by(current_profile).mark_completed!(completed)
    Calendar::DayCardBroadcaster.call(event: day.event)

    render turbo_stream: toast(:success, t(day.event.completion_notice_key(completed, day, current_profile)))
  end
end
