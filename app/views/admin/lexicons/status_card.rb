# frozen_string_literal: true

# Everything about the import itself in one card: its status, a bar of its
# steps, what it is doing now or how it ended, how long it took, its source.
class Views::Admin::Lexicons::StatusCard < Views::Base
  include Phlex::Rails::Helpers::DistanceOfTimeInWords
  include Phlex::Rails::Helpers::NumberWithDelimiter

  # worker_alive: whether a Solid Queue worker is there; nil where that can't be seen.
  def initialize(import:, worker_alive:)
    @import = import
    @worker_alive = worker_alive
  end

  def view_template
    status = @import&.status || "none"
    problem = job_problem
    render Components::Report::StatusCard.new(tone: Views::Admin::Lexicons::StatusBadge.look(status).tone, action: problem&.last) do |card|
      card.head do
        render Views::Admin::Lexicons::StatusBadge.new(status: status)
        card.time { t("admin.lexicons.show.started", time: l(@import.started_at, format: :short)) } if @import&.started_at
      end
      next p(class: "report-hint") { t("admin.lexicons.not_imported") } unless @import

      step_bar if @import.steps.any?
      if problem
        card.now { t("admin.lexicons.progress.#{problem.first}") }
      elsif @import.running?
        now_line(card)
      else
        outcome_line(card)
      end
      card.times(times)
      card.source(@import.source_url)
    end
  end

  private

  # Why a running import isn't moving, and whether the admin must act: [key, action].
  def job_problem
    return unless @import&.running?
    return [ "stopping", false ] if @import.cancel_requested_at

    case @import.job_state
    when :missing then [ "job_missing", true ]
    when :failed then [ "job_failed", true ]
    when :queued then [ @worker_alive == false ? "no_worker" : "queued", @worker_alive == false ]
    end
  end

  def step_bar
    steps = @import.steps
    done = steps.count { _1["status"] == "ok" }
    render Components::Report::SegmentBar.new(segments: steps.map { Views::Admin::Lexicons::Steps::LOOKS.fetch(_1["status"].to_s).tone },
                                              label: t("admin.lexicons.show.steps_done", done: done, total: steps.size))
  end

  def now_line(card)
    step = @import.steps.find { _1["status"] == "running" }
    card.now do
      plain step ? "#{t("admin.lexicons.steps.#{step["name"]}")}: #{step["detail"].presence || t("admin.lexicons.progress.starting")}" :
                   t("admin.lexicons.progress.starting")
    end
  end

  def outcome_line(card)
    if @import.failed?
      card.now do
        strong { t("admin.lexicons.failed_at", step: t("admin.lexicons.steps.#{@import.failed_step}", default: @import.failed_step.to_s)) }
        plain " #{@import.error.to_s.truncate(200)}"
      end
    elsif @import.lemma_count.positive?
      card.now { t("admin.lexicons.nouns", count: @import.lemma_count, formatted: number_with_delimiter(@import.lemma_count)) }
    end
  end

  def times
    if @import.running?
      updated = @import.report["updated_at"].presence && Time.zone.parse(@import.report["updated_at"])
      [ (t("admin.lexicons.progress.running_for", time: time_ago_in_words(@import.started_at)) if @import.started_at),
        (t("admin.lexicons.progress.updated", time: time_ago_in_words(updated)) if updated) ]
    elsif @import.started_at && @import.finished_at
      [ t("admin.lexicons.show.took", time: distance_of_time_in_words(@import.started_at, @import.finished_at)) ]
    end
  end
end
