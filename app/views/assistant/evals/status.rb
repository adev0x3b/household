# frozen_string_literal: true

# Every eval status's look, in one place: a run's (running, paused,
# finished, crashed), a scenario run's (queued, running, passed, failed, and
# error, which is not scored) and a tool call's (running, ok, failed). Each
# is shown as an icon with its word (Components::StatusBadge) or as a mark
# beside its name, never as colour alone.
module Views::Assistant::Evals::Status
  RUN = {
    running: Components::StatusLook.new(tone: :warning).busy,
    paused: Components::StatusLook.new(tone: :neutral, icon: "fa-pause"),
    finished: Components::StatusLook.new(tone: :good, icon: "fa-flag-checkered"),
    crashed: Components::StatusLook.new(tone: :critical, icon: "fa-triangle-exclamation")
  }.freeze
  CASE = {
    "queued" => Components::StatusLook.new(tone: :neutral, icon: "fa-clock"),
    "running" => Components::StatusLook.new(tone: :warning).busy,
    "passed" => Components::StatusLook.new(tone: :good, icon: "fa-circle-check"),
    "failed" => Components::StatusLook.new(tone: :critical, icon: "fa-circle-xmark"),
    "error" => Components::StatusLook.new(tone: :warning, icon: "fa-triangle-exclamation")
  }.freeze
  TOOL = {
    "running" => Components::StatusLook.new(tone: :warning).busy,
    "ok" => Components::StatusLook.new(tone: :good, icon: "fa-circle-check"),
    "failed" => Components::StatusLook.new(tone: :critical, icon: "fa-circle-xmark")
  }.freeze

  module_function

  def run(status) = RUN.fetch(status.to_sym)
  def scenario(state) = CASE.fetch(state.to_s)
  def tool(state) = TOOL.fetch(state.to_s)
end
