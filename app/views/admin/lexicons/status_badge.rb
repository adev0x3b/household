# frozen_string_literal: true

# An import's status as a pill (Components::StatusBadge): icon + word,
# never color alone. ::look is the same status's look for the status card.
class Views::Admin::Lexicons::StatusBadge < Views::Base
  LOOKS = {
    "active" => Components::StatusLook.new(tone: :good, icon: "fa-circle-check"),
    "failed" => Components::StatusLook.new(tone: :critical, icon: "fa-circle-xmark"),
    "running" => Components::StatusLook.new(tone: :warning).busy,
    "unchanged" => Components::StatusLook.new(tone: :warning, icon: "fa-equals"),
    "awaiting_review" => Components::StatusLook.new(tone: :warning, icon: "fa-hourglass-half"),
    "superseded" => Components::StatusLook.new(tone: :neutral, icon: "fa-clock-rotate-left"),
    "cancelled" => Components::StatusLook.new(tone: :neutral, icon: "fa-circle-stop"),
    "none" => Components::StatusLook.new(tone: :neutral, icon: "fa-circle-minus")
  }.freeze

  def self.look(status) = LOOKS.fetch((status || "none").to_s)

  # label: a word of its own (the agent evals' "Passed"), else the import status's.
  def initialize(status:, label: nil)
    @status = (status || "none").to_s
    @label = label
  end

  def view_template
    render self.class.look(@status).badge(label: @label || t("admin.lexicons.statuses.#{@status}"))
  end
end
