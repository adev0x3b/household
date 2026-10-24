# frozen_string_literal: true

# A run in progress on GitHub. What it is doing now is announced as a
# status, since the frame it lives in is re-rendered while it runs.
class Views::Admin::Deliveries::RunCard < Views::Base
  # A step's segment in the bar, by GitHub's word for where it is; one
  # still to start, or in a word this page doesn't know, stays neutral.
  STEP_TONES = { "success" => :good, "failure" => :critical, "in_progress" => :warning, "cancelled" => :neutral, "skipped" => :neutral }.freeze

  # jobs: what the run is doing (Delivery::Github::Job), each with its steps.
  def initialize(run:, jobs:)
    @run = run
    @jobs = jobs
  end

  def view_template
    steps = @jobs.flat_map(&:steps)
    now = @jobs.find(&:live?)
    render Components::Report::StatusCard.new(tone: :warning, compact: true, id: "deployment-run-#{@run.id}") do |card|
      card.head do
        render Views::Admin::Deliveries::Activity::LIVE_RUN.badge(label: t("admin.deployment.activity.statuses.#{@run.status}", default: @run.status.humanize))
        a(href: @run.html_url, class: "deployment__run-title", target: "_blank", rel: "noopener noreferrer") { "##{@run.number} · #{@run.title}" }
        card.time { time_ago(@run.created_at) } if @run.created_at
      end
      if steps.any?
        render Components::Report::SegmentBar.new(segments: steps.map { STEP_TONES.fetch(_1.state, :neutral) },
                                                  label: t("admin.deployment.run.steps", done: steps.count { _1.state == "success" }, total: steps.size))
      end
      card.now(role: "status") do
        if now
          step = now.steps.find { _1.status == "in_progress" }
          strong { now.name }
          plain " · #{step.name}" if step
        else
          plain t("admin.deployment.run.waiting")
        end
      end
    end
  end
end
