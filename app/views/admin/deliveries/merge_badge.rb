# frozen_string_literal: true

# The dev card and the merge modal both show whether dev's branch can
# merge, and must word each state the same way.
class Views::Admin::Deliveries::MergeBadge < Views::Base
  LOOKS = {
    ready: Components::StatusLook.new(tone: :good, icon: "fa-code-merge"),
    ci_running: Components::StatusLook.new(tone: :warning).busy,
    ci_failed: Components::StatusLook.new(tone: :critical),
    ci_none: Components::StatusLook.new(tone: :neutral, icon: "fa-hourglass"),
    draft: Components::StatusLook.new(tone: :neutral, icon: "fa-pen"),
    merged: Components::StatusLook.new(tone: :neutral, icon: "fa-code-merge"),
    none: Components::StatusLook.new(tone: :neutral)
  }.freeze

  # `state` is one of Delivery::Pipeline#merge_state's.
  def initialize(state:)
    @state = state
  end

  def view_template
    render LOOKS.fetch(@state).badge(label: t("admin.deployment.environment.merge_states.#{@state}"))
  end
end
