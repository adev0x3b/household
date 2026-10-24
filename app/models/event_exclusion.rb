# frozen_string_literal: true

# A day removed from a series (time nil), or one slot of a day (time set):
# what Event#occurrences_between leaves out, iCalendar's EXDATE.
class EventExclusion < ApplicationRecord
  belongs_to :event

  self.skip_time_zone_conversion_for_attributes = [ :time ]

  validates :date, presence: true
  validates :date, uniqueness: { scope: %i[event_id time] }

  def time_string = time&.strftime("%H:%M")
end
