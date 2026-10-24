# frozen_string_literal: true

# A scenario's results in the last runs that played it, oldest first: one
# mark per run (passed every time, some, none, or not scored), each opening
# its run. Icon and tone together, and the run's model, date and count as
# the mark's name.
class Views::Assistant::Evals::HistoryStrip < Views::Base
  RUNS = 8

  # runs: the recent ones, newest first; the scenario's own last RUNS are shown.
  def initialize(scenario:, runs:)
    @scenario = scenario
    @runs = runs.select { |run| run.pass_counts.key?(scenario.name) }.first(RUNS).reverse
  end

  def view_template
    return span(class: "eval-history eval-history--none") { t("assistant.evals.history.none") } if @runs.empty?

    ol(class: "eval-history", aria: { label: t("assistant.evals.history.label", name: @scenario.name) }) do
      @runs.each { |run| mark(run) }
    end
  end

  private

  def mark(run)
    passed, scored, errors = run.pass_counts.fetch(@scenario.name)
    look = Views::Assistant::Evals::PassBadge::LOOKS.fetch(Views::Assistant::Evals::PassBadge.kind(passed, scored))
    label = t("assistant.evals.history.mark", model: run.model, date: (run.started_at ? l(run.started_at, format: :short) : run.id),
                                              passed: passed, scored: scored, errors: errors)
    li do
      a(href: assistant_evals_run_path(run.id), class: "eval-history__mark", title: label, aria: { label: label }) do
        render look.mark
      end
    end
  end
end
