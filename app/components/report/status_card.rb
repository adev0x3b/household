# frozen_string_literal: true

# The one card about the job a report page shows (an import, an eval run):
# its status (a Components::StatusBadge), what it's doing now or how
# it ended, the times. A left border in the status's tone; `action:` tints
# it when the reader has to do something. See "Report pages" in
# docs/architecture/front-end.md.
#
#   render Components::Report::StatusCard.new(tone: :warning) do |card|
#     card.head { render Components::StatusBadge.new(…); card.time { "Started …" } }
#     render Components::Report::SegmentBar.new(…)
#     card.now { "Downloading: 40%" }
#     card.times([ "running for 2 minutes", "updated 3 s ago" ])
#   end
class Components::Report::StatusCard < Components::Base
  # tone: one of Components::StatusLook's. id/data: for a card a poll
  # replaces (the eval run's #eval-live-status).
  def initialize(tone:, action: false, id: nil, data: {}, compact: false)
    raise ArgumentError, "unknown tone: #{tone.inspect}" unless Components::StatusLook.tone?(tone)

    @tone = tone
    @action = action
    @id = id
    @data = data
    @compact = compact
  end

  def view_template(&)
    classes = [ "report-status", "report-status--#{@tone}", ("report-status--action" if @action), ("report-status--compact" if @compact) ]
    div(id: @id, class: classes.compact.join(" "), data: @data, &)
  end

  def head(&) = div(class: "report-status__head", &)
  def time(&) = span(class: "report-status__time", &)
  def now(**attributes, &) = p(class: "report-status__now", **attributes, &)

  def times(parts)
    parts = Array(parts).compact
    p(class: "report-status__times") { parts.join(" · ") } if parts.any?
  end

  def source(text)
    p(class: "report-status__source", title: text) { text } if text.present?
  end
end
