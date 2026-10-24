# frozen_string_literal: true

# What the evals' overview page says, from the recent runs (newest first,
# no Try runs) and the scenario files: how the latest run did against the
# one before it on the same model, the pass rate run after run, each model
# side by side, and the scenarios that fail most.
module AssistantEval
  class Overview
    TREND_RUNS = 12
    ATTENTION = 5

    Model = Data.define(:name, :provider, :runs, :latest, :best)
    # flaky: in the latest run it passed some repetitions and failed others.
    Attention = Data.define(:scenario, :passed, :scored, :last_failed, :flaky)

    attr_reader :runs, :scenarios

    def initialize(runs:, scenarios:)
      @runs = runs
      @scenarios = scenarios
    end

    # Runs with something scored, and not so much unscored that the rate
    # means nothing (RunFile#unreliable?) — those still appear in the list
    # of runs, flagged, but never as a headline or a point on the trend.
    def scored_runs = @scored_runs ||= runs.select { |run| run.scored.positive? && !run.unreliable? }

    def latest = scored_runs.first

    # The run before the latest on the same model: the only fair comparison.
    def previous
      latest && scored_runs.drop(1).find { |run| run.model == latest.model }
    end

    # Pass rates in %, oldest first, for the chart and the tile's sparkline.
    def trend = scored_runs.first(TREND_RUNS).reverse

    def self.percent(run) = run&.pass_rate && (run.pass_rate.first * 100).round(1)

    # Seconds, or tokens in, per scenario run: comparable across runs of any size.
    def self.seconds_per_case(run)
      return unless run&.done&.positive?

      (run.results.sum { |result| result["seconds"].to_f } / run.done).round(1)
    end

    def self.tokens_per_case(run)
      return unless run&.done&.positive?

      (run.tokens[:input] / run.done.to_f).round
    end

    # One entry per model that answered, the one run most recently first.
    def models
      scored_runs.group_by(&:model).map do |name, list|
        Model.new(name: name, provider: list.first.provider, runs: list.size, latest: list.first,
                  best: list.map { |run| run.pass_rate.first }.max)
      end
    end

    # The scenarios (still on file) that failed most over the recent runs,
    # worst first; `last_failed` is the newest run where one did.
    def attention
      names = scenarios.map(&:name)
      totals = Hash.new { |hash, key| hash[key] = { passed: 0, scored: 0, last_failed: nil } }
      scored_runs.each do |run|
        run.pass_counts.slice(*names).each do |name, (passed, scored, _errors)|
          entry = totals[name]
          entry[:passed] += passed
          entry[:scored] += scored
          entry[:last_failed] ||= run if passed < scored
        end
      end
      flaky = latest&.flaky_scenarios || []
      totals.select { |_name, entry| entry[:passed] < entry[:scored] }
        .sort_by { |name, entry| [ entry[:passed].fdiv(entry[:scored]), name ] }
        .first(ATTENTION)
        .map { |name, entry| Attention.new(scenario: name, flaky: flaky.include?(name), **entry) }
    end
  end
end
