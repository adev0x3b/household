# frozen_string_literal: true

# Says when a run's pass rate can't be trusted, because too much of it went
# unscored when the model server went away mid-run
# (AssistantEval::RunFile#unreliable?), and whether the task gave up
# waiting. Nothing when the run is fine.
class Views::Assistant::Evals::ReliabilityBadge < Views::Base
  def initialize(run:)
    @run = run
  end

  def view_template
    return unless @run.unreliable?

    total = [ @run.total, @run.done ].max
    label = t("assistant.evals.run.unreliable", errors: @run.errors, total: total)
    render Components::StatusBadge.new(tone: :warning, icon: "fa-triangle-exclamation", label: label,
                                       title: t(@run.gave_up? ? "assistant.evals.run.unreliable_gave_up_title" : "assistant.evals.run.unreliable_title"))
  end
end
