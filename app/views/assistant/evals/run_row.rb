# frozen_string_literal: true

# One run in a list (the Runs page, the overview's latest runs): its
# status, model and provider, when and how long, a bar of what passed, the
# score with its 95% interval. The run in progress can be paused, resumed
# or cancelled from its row; a Try from the scenario form is marked so.
class Views::Assistant::Evals::RunRow < Views::Base
  def initialize(run:)
    @run = run
    @words = ::Assistant::Evals::RunWords.new(run)
  end

  def view_template
    li(class: "eval-runs__row") do
      div(class: "eval-runs__main") do
        div(class: "eval-runs__head") do
          render Views::Assistant::Evals::RunBadge.new(status: @run.status)
          a(href: assistant_evals_run_path(@run.id), class: "eval-runs__title") { @words.model_line }
          span(class: "report-tag") { t("assistant.evals.run.try_tag", name: @run.data["draft"]) } if @run.draft?
        end
        p(class: "report-hint") { [ (l(@run.started_at, format: :short) if @run.started_at), @words.timing, @words.progress ].compact.join(" · ") }
      end
      div(class: "eval-runs__score") do
        rate
        render Views::Assistant::Evals::RateBar.new(run: @run, label: @words.progress)
        render Views::Assistant::Evals::PassBadge.new(count: [ @run.passed, @run.scored, @run.errors ]) if @run.done.positive?
        render Views::Assistant::Evals::ReliabilityBadge.new(run: @run)
      end
      actions
    end
  end

  private

  def rate
    return unless @words.scored?

    span(class: "eval-runs__rate", title: t("assistant.evals.noise_title")) do
      strong(class: "eval-runs__percent") { @words.rate }
      span(class: "eval-runs__interval") { t("assistant.evals.run.interval", low: @words.low, high: @words.high) }
    end
  end

  # Only a run that's going (or paused) has anything to do on its row.
  def actions
    return unless @run.active?

    div(class: "eval-runs__actions") do
      if @run.running?
        render Components::ItemAction.new(href: pause_assistant_evals_run_path(@run.id), icon: "fa-pause", method: :post,
                                          label: t("assistant.evals.run.pause"))
      else
        render Components::ItemAction.new(href: resume_assistant_evals_run_path(@run.id), icon: "fa-play", method: :post,
                                          label: t("assistant.evals.run.resume"))
      end
      render Components::ItemAction.new(href: assistant_evals_run_path(@run.id), icon: "fa-stop", method: :delete, danger: true,
                                        label: t("assistant.evals.run.cancel"), confirm: t("assistant.evals.run.cancel_confirm"))
    end
  end
end
