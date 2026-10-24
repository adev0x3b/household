# frozen_string_literal: true

# One eval run: its status card, then the live tracker
# (Views::Assistant::Evals::LiveRun) when the run recorded its events;
# runs from before the tracker show their saved results, one section each.
# Pause, resume and cancel are the navbar's while the run goes.
class Views::Assistant::Evals::Runs::Show < Views::Base
  def initialize(run:)
    @run = run
    @events = AssistantEval::RunEvents.for(run)
  end

  def page_title
    @run.draft? ? t("assistant.evals.run.draft_title", name: @run.data["draft"]) : t("assistant.evals.run.title", model: @run.model)
  end

  def navbar_controls
    return unless @run.active?

    pause_or_resume =
      if @run.running?
        Components::Action.new(href: routes.pause_assistant_evals_run_path(@run.id), icon: "fa-pause", method: :post,
                               label: t("assistant.evals.run.pause"))
      else
        Components::Action.new(href: routes.resume_assistant_evals_run_path(@run.id), icon: "fa-play", method: :post,
                               label: t("assistant.evals.run.resume"))
      end
    cancel = Components::Action.new(href: routes.assistant_evals_run_path(@run.id), icon: "fa-stop", method: :delete,
                                    label: t("assistant.evals.run.cancel"), confirm: t("assistant.evals.run.cancel_confirm"))
    Components::PageControls.new(actions: [ pause_or_resume, cancel ])
  end

  def view_template
    div(class: "report-page report-page--wide evals") do
      render Components::PageHeader.new(title: page_title, back_href: assistant_evals_runs_path, back_label: t("assistant.evals.back_to_runs"))
      if @events.exist?
        render Views::Assistant::Evals::LiveRun.new(run: @run, events: @events)
      else
        saved_results
      end
    end
  end

  private

  def saved_results
    render Views::Assistant::Evals::RunStatusCard.new(run: @run)
    if @run.status == :crashed
      render Components::Disclosure.new(key: "eval-#{@run.id}-log", title: t("assistant.evals.run.log"), open: true) do
        pre(class: "eval-run__log") { @run.log_tail }
      end
    end
    return p(class: "report-hint") { t("assistant.evals.run.no_results") } if @run.results.empty?

    @run.results.each_with_index do |result, index|
      render Views::Assistant::Evals::RunResult.new(result: result, key: "eval-#{@run.id}-#{index}")
    end
  end
end
