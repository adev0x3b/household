# frozen_string_literal: true

# The one card about an eval run (Components::Report::StatusCard): its
# status, model and provider, when it started; a bar with one segment per
# scenario run in its state's tone; what the agent is doing now (with the
# live clock, eval_live_controller.js), the score with its 95% interval, the
# time and tokens.
#
# On the run's page it's #eval-live-status, which every poll of the live
# tracker replaces (its data-last-at / data-phase feed the clock). Compact,
# it's the banner on the scenarios page and the Try result (RunPanel), with
# a link to the run.
class Views::Assistant::Evals::RunStatusCard < Views::Base
  DOM_ID = "eval-live-status"

  def initialize(run:, events: nil, compact: false)
    @run = run
    @events = events&.exist? ? events : nil
    @compact = compact
    @words = ::Assistant::Evals::RunWords.new(run)
  end

  def view_template
    render Components::Report::StatusCard.new(tone: Views::Assistant::Evals::Status.run(@run.status).tone, compact: @compact, id: (DOM_ID unless @compact), data: live_data) do |card|
      card.head do
        render Views::Assistant::Evals::RunBadge.new(status: @run.status)
        span(class: "eval-run__model") { @words.model_line }
        span(class: "report-tag") { t("assistant.evals.run.try_tag", name: @run.data["draft"]) } if @run.draft?
        card.time { t("assistant.evals.run.started", time: l(@run.started_at, format: :short)) } if @run.started_at
      end
      render Components::Report::SegmentBar.new(segments: segments, label: @words.progress)
      card.now(data: { eval_live_target: "clock" }) if live?
      score_line
      card.times([ @words.progress, @words.timing, tokens ])
      a(href: assistant_evals_run_path(@run.id), class: "eval-run__open") { t("assistant.evals.run.open") } if @compact
    end
  end

  private

  def live? = !@compact && @events.present?

  # What the live clock reads (eval_live_controller.js#updateClock).
  def live_data
    return {} unless live?

    { eval_live_target: "status", last_at: @events.last_at, phase: phase_text(@run.running? ? @events.now : nil) }
  end

  def phase_text(now)
    case now&.dig("phase")
    when "model" then t("assistant.evals.live.waiting_model")
    when "tool" then t("assistant.evals.live.running_tool", tool: now["tool"])
    end
  end

  # One per scenario run: from the live events, else the saved results and
  # the ones still to come.
  def segments
    if @events
      @events.cases.map { |kase| Views::Assistant::Evals::Status.scenario(kase["state"]).tone }
    else
      done = @run.results.map { |result| Views::Assistant::Evals::Status.scenario(AssistantEval::RunFile.status(result)).tone }
      done + ([ :neutral ] * [ @run.total - @run.done, 0 ].max)
    end
  end

  def score_line
    return p(class: "report-hint") { t("assistant.evals.run.starting") } if @run.done.zero?

    p(class: "eval-run__score") do
      if @words.scored?
        strong(class: "eval-run__percent") { @words.rate }
        span(class: "eval-run__rate", title: t("assistant.evals.noise_title")) { t("assistant.evals.run.passed_interval", low: @words.low, high: @words.high) }
      end
      render Views::Assistant::Evals::PassBadge.new(count: [ @run.passed, @run.scored, @run.errors ])
      render Views::Assistant::Evals::ReliabilityBadge.new(run: @run)
    end
  end

  def tokens
    tokens = @run.tokens
    return unless tokens[:input].positive?

    t("assistant.evals.live.run_tokens", input: format_figure(tokens[:input], :count), output: format_figure(tokens[:output], :count), largest: format_figure(tokens[:largest_step], :count))
  end
end
