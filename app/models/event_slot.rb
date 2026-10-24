# frozen_string_literal: true

# One of the times of a series' day, as FHIR's Timing writes them: a clock
# time ("08:00") or an anchor from the EventTiming value set (CM with
# breakfast, CD with lunch, CV with dinner, HS at bedtime) resolved to the
# household's usual hour (Events::TimesOfDay). A series with no slots is one
# untimed day; a Medication taken twice a day has two.
class EventSlot < ApplicationRecord
  belongs_to :event

  after_save { event.mark_changed! if saved_changes? }
  after_destroy { event.mark_changed! unless destroyed_by_association }

  self.skip_time_zone_conversion_for_attributes = [ :time ]

  validates :time, presence: true
  validates :time, uniqueness: { scope: :event_id }
  validates :position, presence: true, uniqueness: { scope: :event_id }
  validates :anchor, inclusion: { in: Events::TimesOfDay::ANCHORS.keys }, allow_nil: true

  def time_string = time.strftime("%H:%M")

  # Rows for a list of entries ("08:00", "CV"), in clock order.
  def self.rows_for(entries)
    Events::TimesOfDay.expand(Events::TimesOfDay.normalize(entries)).each_with_index.map do |(time, anchor), position|
      new(time: time, anchor: anchor, position: position)
    end
  end
end
