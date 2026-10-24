# frozen_string_literal: true

# One model on the overview (an AssistantEval::Overview::Model): how its
# latest run did, its best, how many runs and how fast. The card opens that
# latest run.
class Views::Assistant::Evals::ModelCard < Views::Base
  def initialize(model:)
    @model = model
    @run = model.latest
    @words = ::Assistant::Evals::RunWords.new(@run)
  end

  def view_template
    a(href: assistant_evals_run_path(@run.id), class: "eval-model") do
      span(class: "eval-model__head") do
        render Components::Icon.new("fa-microchip", class: "eval-model__icon")
        span(class: "eval-model__name") { @model.name }
        span(class: "eval-model__provider") { @words.provider }
      end
      span(class: "eval-model__rate", title: t("assistant.evals.noise_title")) do
        strong { @words.rate }
        span { t("assistant.evals.run.interval", low: @words.low, high: @words.high) }
      end
      render Views::Assistant::Evals::RateBar.new(run: @run, label: @words.progress)
      span(class: "eval-model__facts") { facts.join(" · ") }
    end
  end

  private

  def facts
    seconds = AssistantEval::Overview.seconds_per_case(@run)
    [ t("assistant.evals.overview.models.runs", count: @model.runs),
      t("assistant.evals.overview.models.best", rate: ::Assistant::Evals::RunWords.percent(@model.best)),
      (t("assistant.evals.overview.models.pace", seconds: format_figure(seconds, :count)) if seconds),
      (l(@run.started_at, format: :short) if @run.started_at) ].compact
  end
end
