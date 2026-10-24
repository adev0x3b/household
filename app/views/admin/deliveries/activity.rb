# frozen_string_literal: true

# Presses GitHub doesn't list yet come first, so a press shows the moment it
# is made rather than when its run appears.
class Views::Admin::Deliveries::Activity < Views::Base
  # How a run ended, by GitHub's word for it. GitHub may add a word this
  # page doesn't know yet, and that run still shows, in the neutral look.
  RUN_LOOKS = {
    "success" => Components::StatusLook.new(tone: :good),
    "failure" => Components::StatusLook.new(tone: :critical),
    "timed_out" => Components::StatusLook.new(tone: :critical),
    "startup_failure" => Components::StatusLook.new(tone: :critical),
    "action_required" => Components::StatusLook.new(tone: :warning)
  }.freeze
  LIVE_RUN = Components::StatusLook.new(tone: :warning).busy
  OTHER_RUN = Components::StatusLook.new(tone: :neutral)
  REQUEST_LOOKS = {
    "requested" => Components::StatusLook.new(tone: :neutral).busy,
    "running" => Components::StatusLook.new(tone: :warning).busy,
    "succeeded" => Components::StatusLook.new(tone: :good),
    "failed" => Components::StatusLook.new(tone: :critical),
    "lost" => Components::StatusLook.new(tone: :neutral)
  }.freeze

  def initialize(runs:, requests: [])
    @runs = runs
    @requests = requests.reject { |request| request.run_id && runs.any? { _1.id == request.run_id } }
  end

  def view_template
    render Components::Panel.new(title: t("admin.deployment.activity.title"), hint: t("admin.deployment.activity.hint", count: Delivery::Pipeline::RUNS)) do
      if @runs.empty? && @requests.empty?
        p(class: "report-hint") { t("admin.deployment.activity.none") }
      else
        ul(class: "report-rows deployment__runs", aria: { live: "polite" }) do
          @requests.each { |request| request_row(request) }
          @runs.each { |run| row(run) }
        end
      end
    end
  end

  private

  def request_row(request)
    li(class: "deployment__run deployment__run--request", id: "deployment-request-#{request.id}") do
      render REQUEST_LOOKS.fetch(request.status).badge(label: t("admin.deployment.activity.request_statuses.#{request.status}"))
      span(class: "deployment__run-title") do
        plain t("admin.deployment.activity.request.#{request.action}", destination: request.destination && t("admin.deployment.destinations.#{request.destination}"),
                                                                       ref: request.ref, version: request.short_version || Delivery::Pipeline::BRANCH)
        plain " · #{request.reason}" if request.reason.present?
      end
      span(class: "deployment__run-meta") { t("admin.deployment.activity.by", actor: request.profile.username, time: time_ago(request.created_at)) }
      span(class: "deployment__run-meta") { request.summary } if request.failed? && request.summary.present?
    end
  end

  def row(run)
    li(class: "deployment__run") do
      render look(run).badge(label: t("admin.deployment.activity.statuses.#{run.state}", default: run.state.humanize))
      a(href: run.html_url, class: "deployment__run-title", target: "_blank", rel: "noopener noreferrer") { "##{run.number} · #{run.title}" }
      span(class: "deployment__run-meta") { t("admin.deployment.activity.by", actor: run.actor, time: time_ago(run.created_at)) }
    end
  end

  def look(run) = run.live? ? LIVE_RUN : RUN_LOOKS.fetch(run.state, OTHER_RUN)
end
