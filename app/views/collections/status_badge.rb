# frozen_string_literal: true

# A collection's status as a pill: going on, paused or done, each with its
# own sign. Only a pause asks for attention.
class Views::Collections::StatusBadge < Views::Base
  LOOKS = {
    "active" => Components::StatusLook.new(tone: :neutral, icon: "fa-play"),
    "paused" => Components::StatusLook.new(tone: :warning, icon: "fa-pause"),
    "completed" => Components::StatusLook.new(tone: :neutral, icon: "fa-circle-check")
  }.freeze

  def initialize(status:)
    @status = status.to_s
  end

  def view_template
    render LOOKS.fetch(@status).badge(label: t("collections.status.#{@status}"))
  end
end
