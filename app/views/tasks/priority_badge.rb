# frozen_string_literal: true

# A task's priority as a pill, on its calendar card and on Home: the more
# pressing, the stronger the tone, and always the word.
class Views::Tasks::PriorityBadge < Views::Base
  LOOKS = {
    "low" => Components::StatusLook.new(tone: :neutral, icon: "fa-flag"),
    "medium" => Components::StatusLook.new(tone: :neutral, icon: "fa-flag"),
    "high" => Components::StatusLook.new(tone: :warning, icon: "fa-flag"),
    "urgent" => Components::StatusLook.new(tone: :critical, icon: "fa-flag")
  }.freeze
  PRESSING = %w[high urgent].freeze

  # Whether a priority is worth a pill where tasks are many, as on a
  # calendar: low and medium are the ordinary run of tasks, and a pill on
  # each would leave nothing to stand out.
  def self.pressing?(priority) = PRESSING.include?(priority.to_s)

  def initialize(priority:)
    @priority = priority.to_s
  end

  def view_template
    render LOOKS.fetch(@priority).badge(label: t("tasks.priority.#{@priority}"))
  end
end
