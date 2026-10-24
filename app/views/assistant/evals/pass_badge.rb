# frozen_string_literal: true

# One result (passed, failed or error), or a scenario across runs
# ([passed, scored, errors] reads "2/3", plus "⚠ 1" when some runs erred),
# as a Components::StatusBadge with its icon and words. An error is the
# plumbing failing (the model server unreachable, the harness crashed), so
# errors are shown apart and never counted as fails.
class Views::Assistant::Evals::PassBadge < Views::Base
  # A result's look, here and in a scenario's history (HistoryStrip).
  LOOKS = {
    pass: Components::StatusLook.new(tone: :good, icon: "fa-circle-check"),
    mixed: Components::StatusLook.new(tone: :warning, icon: "fa-circle-half-stroke"),
    fail: Components::StatusLook.new(tone: :critical, icon: "fa-circle-xmark"),
    error: Components::StatusLook.new(tone: :warning, icon: "fa-triangle-exclamation")
  }.freeze
  RESULTS = { "passed" => :pass, "failed" => :fail, "error" => :error }.freeze

  # How a scenario did across runs: passed every time, some, none, or never
  # scored because every run erred.
  def self.kind(passed, scored)
    return :error if scored.zero?
    return :pass if passed == scored

    passed.zero? ? :fail : :mixed
  end

  def initialize(status: nil, count: nil)
    @status = status
    @passed, @scored, @errors = count
  end

  def view_template
    if @status
      kind = RESULTS.fetch(@status.to_s)
      badge(kind, t("assistant.evals.result.#{kind}"))
    else
      badge(self.class.kind(@passed, @scored), t("assistant.evals.result.count", passed: @passed, scored: @scored)) if @scored.to_i.positive?
      if @errors.to_i.positive?
        badge(:error, @scored.to_i.positive? ? @errors.to_s : t("assistant.evals.result.not_scored", count: @errors),
              title: t("assistant.evals.result.errors_title", count: @errors))
      end
    end
  end

  private

  def badge(kind, label, title: nil)
    render LOOKS.fetch(kind).badge(label: label, title: title)
  end
end
