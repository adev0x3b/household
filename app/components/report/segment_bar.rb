# frozen_string_literal: true

# How far along a job is, at a glance: one segment per step (or per case),
# each in its status's tone (one of Components::StatusLook's). An image to
# assistive technology, named by `label` ("3 of 5 steps done").
#
#   render Components::Report::SegmentBar.new(segments: %i[good good warning neutral], label: t("…"))
class Components::Report::SegmentBar < Components::Base
  def initialize(segments:, label:)
    unknown = segments.reject { Components::StatusLook.tone?(_1) }
    raise ArgumentError, "unknown tones: #{unknown.uniq.inspect}" if unknown.any?

    @segments = segments
    @label = label
  end

  def view_template
    return if @segments.empty?

    div(class: "report-segments", role: "img", aria: { label: @label }) do
      @segments.each { |tone| span(class: "report-segments__segment report-segments__segment--#{tone}") }
    end
  end
end
