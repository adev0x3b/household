# frozen_string_literal: true

# The evals' front page (an AssistantEval::Overview): how the assistant is
# doing, before any list. The latest run against the one before it as four
# headline figures, the pass rate run after run, the scenarios that fail
# most (each can be opened or run alone), every model side by side, and the
# latest runs. A run in progress shows on top. Scenarios and runs have
# their own pages (Views::Assistant::Evals::Tabs).
class Views::Assistant::Evals::Overview < Views::Base
  LATEST_RUNS = 5

  def initialize(overview:, running:)
    @overview = overview
    @running = running
  end

  def page_title = t("assistant.evals.title")

  # Run (the run modal, every scenario) waits while another run goes.
  def navbar_controls
    return if @running

    run = Components::Action.new(href: routes.new_assistant_evals_run_path, icon: "fa-play", turbo_stream: true,
                                 label: t("assistant.evals.run_button"))
    Components::PageControls.new(actions: [ run ])
  end

  def view_template
    div(class: "report-page report-page--wide evals") do
      render Components::PageHeader.new(title: t("assistant.evals.title"))
      render Views::Assistant::Evals::Tabs.new(current: :overview)
      render Views::Assistant::Evals::RunPanel.new(run: @running) if @running
      if @overview.latest
        kpis
        div(class: "eval-overview__columns") do
          trend
          attention
        end
        models
        latest_runs
      else
        render Components::EmptyState.new(icon: "fa-flask-vial", message: t("assistant.evals.overview.empty"))
      end
    end
  end

  private

  def summary = AssistantEval::Overview

  def kpis
    latest = @overview.latest
    previous = @overview.previous
    section(class: "statistics__kpis", aria: { label: t("assistant.evals.overview.kpis.label") }) do
      tile(:pass_rate, "fa-bullseye", metric(summary.percent(latest), summary.percent(previous), :percent, :higher_is_better,
                                             series: @overview.trend.map { |run| summary.percent(run) }),
           footnote: t("assistant.evals.overview.kpis.latest_run", model: latest.model, passed: latest.passed, scored: latest.scored))
      tile(:scenarios, "fa-list-check", metric(@overview.scenarios.size, nil, :count, :neutral), comparison: false,
                                                                                                 footnote: t("assistant.evals.overview.kpis.tags", count: @overview.scenarios.flat_map(&:tags).uniq.size))
      tile(:pace, "fa-stopwatch", metric(summary.seconds_per_case(latest), summary.seconds_per_case(previous), :count, :lower_is_better))
      tile(:tokens, "fa-coins", metric(summary.tokens_per_case(latest), summary.tokens_per_case(previous), :count, :neutral))
    end
  end

  def metric(value, previous, format, polarity, series: [])
    Reports::Metric.new(value: value, previous: previous, format: format, polarity: polarity, series: series)
  end

  def tile(key, icon, metric, footnote: nil, comparison: true)
    render Components::Statistics::StatTile.new(
      metric: metric, icon: icon, label: t("assistant.evals.overview.kpis.#{key}"), hint: t("assistant.evals.overview.kpis.hints.#{key}"),
      footnote: footnote, comparison: comparison,
    )
  end

  def trend
    runs = @overview.trend
    render Components::Statistics::Report.new(title: t("assistant.evals.overview.trend.title"), icon: "fa-chart-line",
                                              description: t("assistant.evals.overview.trend.description", count: runs.size)) do
      render Components::Statistics::Chart.new(
        caption: false,
        chart: Reports::Chart.new(
          kind: :line, title: t("assistant.evals.overview.trend.title"), format: :percent,
          labels: runs.map { |run| run.started_at ? l(run.started_at, format: :short) : run.id },
          series: [ Reports::Chart::Series.new(label: t("assistant.evals.overview.kpis.pass_rate"),
                                               values: runs.map { |run| summary.percent(run) }, color: "series-1") ],
        ),
      )
    end
  end

  def attention
    items = @overview.attention
    render Components::Statistics::Report.new(title: t("assistant.evals.overview.attention.title"), icon: "fa-triangle-exclamation",
                                              description: t("assistant.evals.overview.attention.description")) do
      if items.empty?
        render Components::EmptyState.new(icon: "fa-circle-check", message: t("assistant.evals.overview.attention.none"))
      else
        ul(class: "report-rows eval-attention") { items.each { |item| attention_row(item) } }
      end
    end
  end

  def attention_row(item)
    li(class: "eval-attention__row") do
      div(class: "eval-attention__main") do
        a(href: edit_assistant_evals_scenario_path(item.scenario), class: "eval-attention__name") { item.scenario }
        a(href: assistant_evals_run_path(item.last_failed.id), class: "eval-attention__last") do
          t("assistant.evals.overview.attention.last_failed", time: l(item.last_failed.started_at || Time.current, format: :short))
        end
      end
      render Views::Assistant::Evals::PassBadge.new(count: [ item.passed, item.scored, 0 ])
      if item.flaky
        render Components::StatusBadge.new(tone: :warning, icon: "fa-shuffle", label: t("assistant.evals.overview.attention.flaky"),
                                           title: t("assistant.evals.overview.attention.flaky_title"))
      end
      unless @running
        render Components::ItemAction.new(href: new_assistant_evals_run_path(only: item.scenario), icon: "fa-play", turbo_stream: true,
                                          label: t("assistant.evals.run_scenario", name: item.scenario))
      end
    end
  end

  def models
    render Components::Statistics::Report.new(title: t("assistant.evals.overview.models.title"), icon: "fa-microchip",
                                              description: t("assistant.evals.overview.models.description")) do
      div(class: "eval-models") { @overview.models.each { |model| render Views::Assistant::Evals::ModelCard.new(model: model) } }
    end
  end

  def latest_runs
    render Components::Statistics::Report.new(title: t("assistant.evals.overview.runs.title"), icon: "fa-clock-rotate-left") do
      ol(class: "report-rows eval-runs__list") do
        @overview.runs.first(LATEST_RUNS).each { |run| render Views::Assistant::Evals::RunRow.new(run: run) }
      end
      a(href: assistant_evals_runs_path, class: "eval-overview__more") { t("assistant.evals.overview.runs.all") }
    end
  end
end
