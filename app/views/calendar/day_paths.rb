# frozen_string_literal: true

# The addresses of a day of a series, saved or not yet: its form, the day
# itself (where its form is sent, and what a DELETE removes), its
# completion and its status. Each names the series and the date and, for a
# series taken several times a day, the dose's time.
module Views::Calendar::DayPaths
  private

  def day_form_path(occurrence) = edit_event_day_path(occurrence.event, occurrence.date, **dose_of(occurrence))
  def day_path(occurrence, **options) = event_day_path(occurrence.event, occurrence.date, **dose_of(occurrence), **options)
  def day_completion_path(occurrence) = event_day_completion_path(occurrence.event, occurrence.date, **dose_of(occurrence))
  def day_status_path(occurrence) = event_day_status_path(occurrence.event, occurrence.date, **dose_of(occurrence))

  def dose_of(occurrence) = { time: occurrence.time_string }.compact
end
