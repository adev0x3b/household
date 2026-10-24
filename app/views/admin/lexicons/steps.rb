# frozen_string_literal: true

# The import's steps, one row each with its status, time and detail, and
# then its hand-written data checks; each part says its result in its header.
class Views::Admin::Lexicons::Steps < Views::Admin::Lexicons::Part
  # A step's status, here and in the status card's bar; a hand-written
  # check is "ok" or "failed" like a step.
  LOOKS = {
    "ok" => Components::StatusLook.new(tone: :good, icon: "fa-circle-check"),
    "failed" => Components::StatusLook.new(tone: :critical, icon: "fa-circle-xmark"),
    "running" => Components::StatusLook.new(tone: :warning).busy,
    "waiting" => Components::StatusLook.new(tone: :warning, icon: "fa-hourglass-half"),
    "pending" => Components::StatusLook.new(tone: :neutral, icon: "fa-circle"),
    "skipped" => Components::StatusLook.new(tone: :neutral, icon: "fa-circle-minus"),
    "cancelled" => Components::StatusLook.new(tone: :neutral, icon: "fa-circle-stop")
  }.freeze

  def initialize(import:)
    @import = import
  end

  def view_template
    steps_section
    checks_section if @import.checks.any?
  end

  private

  def steps_section
    steps = @import.steps
    failed = steps.find { _1["status"] == "failed" }
    result = -> do
      if failed
        span(class: "status-tone--critical") { t("admin.lexicons.show.failed_at_step", step: t("admin.lexicons.steps.#{failed["name"]}")) }
      else
        plain t("admin.lexicons.show.steps_done", done: steps.count { _1["status"] == "ok" }, total: steps.size)
      end
    end
    section(@import.id, "steps", title: t("admin.lexicons.show.steps"), open: failed.present? || steps.any? { _1["status"] == "running" }, result: result) do
      ol(class: "lexicons__steps") { steps.each { |step| step_row(step) } }
    end
  end

  def checks_section
    checks = @import.checks
    passed = checks.count { _1["ok"] }
    result = -> { span(class: ("status-tone--critical" if passed < checks.size)) { t("admin.lexicons.show.checks_passed", passed: passed, total: checks.size) } }
    section(@import.id, "checks", title: t("admin.lexicons.show.checks"), open: passed < checks.size, result: result) do
      ul(class: "lexicons__checks") { checks.each { |check| check_row(check) } }
    end
  end

  def step_row(step)
    status = step["status"].to_s
    li(class: "lexicons__step lexicons__step--#{status}") do
      render LOOKS.fetch(status).mark
      span(class: "lexicons__step-name") { t("admin.lexicons.steps.#{step["name"]}") }
      span(class: "lexicons__step-status") { t("admin.lexicons.step_statuses.#{status}") }
      if step["seconds"]
        span(class: "lexicons__step-seconds") { t("admin.lexicons.show.seconds", seconds: step["seconds"]) }
      elsif status == "running" && step["started_at"]
        span(class: "lexicons__step-seconds") { t("admin.lexicons.progress.for", time: time_ago_in_words(Time.zone.parse(step["started_at"]))) }
      end
      p(class: "lexicons__step-detail") { step["detail"] } if step["detail"].present?
    end
  end

  def check_row(check)
    state = check["ok"] ? "ok" : "failed"

    li(class: "lexicons__check lexicons__check--#{state}") do
      render LOOKS.fetch(state).mark(label: t("admin.lexicons.step_statuses.#{state}"))
      code { check["check"] }
      span(class: "lexicons__check-got") { t("admin.lexicons.show.found", got: check["got"]) }
    end
  end
end
