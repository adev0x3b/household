# frozen_string_literal: true

# A link that opens one day of a series (an Occurrence, saved or not yet)
# in its form, right where the reader is (the same turbo-stream pattern as
# the calendar's cards).
#
#   render Views::Home::OccurrenceLink.new(occurrence: row.occurrence) { row.title }
class Views::Home::OccurrenceLink < Views::Base
  include Views::Calendar::DayPaths

  def initialize(occurrence:, **attributes)
    @occurrence = occurrence
    @attributes = attributes
  end

  def view_template(&)
    a(href: day_form_path(@occurrence), data: { turbo_stream: true }, **@attributes, &)
  end
end
