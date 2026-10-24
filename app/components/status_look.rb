# frozen_string_literal: true

# How one status looks wherever it is shown: its tone, and the icon that
# says it without the colour. A kind of status keeps one table of these, so
# a status's tone and icon are written side by side, once, and drawn the
# same way as a pill or as a mark.
class Components::StatusLook < Data.define(:tone, :icon)
  # Each tone's own icon, for a status that needs none more particular.
  TONES = {
    good: "fa-circle-check",
    warning: "fa-triangle-exclamation",
    critical: "fa-circle-exclamation",
    neutral: "fa-circle-info"
  }.freeze

  def self.tone?(tone) = TONES.key?(tone)

  def initialize(tone:, icon: nil)
    raise ArgumentError, "unknown tone: #{tone.inspect}" unless self.class.tone?(tone)

    super(tone:, icon: icon || TONES.fetch(tone))
  end

  # The same status while it is under way: its tone, turning.
  def busy = with(icon: "fa-spinner fa-spin")

  # The status as a pill beside its word.
  def badge(label:, title: nil) = Components::StatusBadge.new(tone:, icon:, label:, title:)

  # The status as an icon alone in its tone, named for whoever can't see it.
  def mark(label: nil, title: nil) = Components::Icon.new(icon, label:, class: "status-tone--#{tone}", **{ title: }.compact)
end
