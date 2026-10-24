# frozen_string_literal: true

# The live tracker for one eval run: its status card (RunStatusCard: what
# the agent is doing now, and for how long), then every scenario run with
# its state beside the timeline of what the agent did: messages, tool
# calls, replies, results. eval_live_controller.js polls
# RunsController#events while the run lives and applies the changes as
# Turbo Streams; a finished run renders whole. Pause, resume and cancel are
# the navbar's (RunsController#show).
class Views::Assistant::Evals::LiveRun < Views::Base
  def initialize(run:, events:)
    @run = run
    @events = events
  end

  def view_template
    div(class: "eval-live",
        data: { controller: "eval-live", eval_live_url_value: events_assistant_evals_run_path(@run.id),
                eval_live_after_value: @events.size, eval_live_active_value: @run.active? }) do
      render Views::Assistant::Evals::RunStatusCard.new(run: @run, events: @events)
      log if @run.status == :crashed
      div(class: "eval-live__body") do
        nav(class: "eval-live__cases", aria: { label: t("assistant.evals.live.cases") }) do
          render Views::Assistant::Evals::LiveCases.new(events: @events)
        end
        section(class: "eval-live__timeline", aria: { label: t("assistant.evals.live.timeline") }) do
          ol(id: "eval-timeline", class: "eval-timeline", data: { eval_live_target: "timeline" }) do
            @events.display.each { |event| render Views::Assistant::Evals::Timeline.for(event) }
          end
        end
      end
    end
  end

  private

  def log
    render Components::Disclosure.new(key: "eval-#{@run.id}-log", title: t("assistant.evals.run.log"), open: true) do
      pre(class: "eval-run__log") { @run.log_tail }
    end
  end
end
