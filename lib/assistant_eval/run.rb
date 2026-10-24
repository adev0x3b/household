# frozen_string_literal: true

module AssistantEval
  # One eval run, as `bin/rails assistant:eval[RUNS,filter]` starts it (the
  # task only reads its arguments): every scenario, RUNS times, each played
  # by a Runner in a rolled-back transaction.
  #
  #   AssistantEval::Run.from_env(ENV, runs: "3", filter: "lab").call   # => the results file
  #
  # Along the way it keeps two files for the eval dashboard: the results
  # (`tmp/assistant_evals/<time>-<model>.json`, or EVAL_RESULTS), rewritten
  # after every result and marked finished at the end (RunFile reads it), and
  # the events beside it (Recorder: the live tracker). An outage mid-run is
  # waited out, not scored: after OUTAGE_AFTER unreachable results in a row
  # it waits for the model server (Outage), up to OUTAGE_WAIT seconds in all,
  # then finishes with what it has, flagged (RunFile#unreliable?). Whoever
  # started it (EVAL_NOTIFY) hears how it went.
  class Run
    NotStarted = Class.new(StandardError)

    MARKS = { "passed" => "✓", "failed" => "✗", "error" => "⚠" }.freeze

    # What the dashboard passes (Launcher), else the task's arguments:
    #   SCENARIOS=a,b       exact scenario names (instead of the filter)
    #   SCENARIO_FILE=path  one scenario file outside eval/assistant/scenarios (an unsaved draft)
    #   SCENARIO_DIR=path   every scenario file in a directory (generated, Lexicon::AgentEval)
    #   EVAL_RESULTS=path   where to write the results
    #   EVAL_NOTIFY=id      the profile to notify when the run ends
    #   EVAL_SKIP_PREFLIGHT=1  start even when the model doesn't answer
    #   EVAL_OUTAGE_AFTER / EVAL_OUTAGE_WAIT / EVAL_OUTAGE_POLL  (3 results, 1800 s, 15 s)
    def self.from_env(env, runs: nil, filter: nil, out: $stdout)
      new(
        scenarios: scenarios_from(env, filter), runs: (runs || 3).to_i, out: out,
        results_path: env["EVAL_RESULTS"].presence, notify: env["EVAL_NOTIFY"].presence,
        draft: env["SCENARIO_FILE"].present?, preflight: env["EVAL_SKIP_PREFLIGHT"].blank?,
        outage: { after: env.fetch("EVAL_OUTAGE_AFTER", 3).to_i, wait: env.fetch("EVAL_OUTAGE_WAIT", 1800).to_f,
                  poll: env.fetch("EVAL_OUTAGE_POLL", 15).to_f },
        filter: env["SCENARIOS"].presence || filter
      )
    end

    def self.scenarios_from(env, filter)
      if env["SCENARIO_FILE"].present? then [ Scenario.load(env["SCENARIO_FILE"]) ]
      elsif env["SCENARIO_DIR"].present? then Dir[File.join(env["SCENARIO_DIR"], "*.yml")].map { Scenario.load(_1) }
      elsif env["SCENARIOS"].present?
        names = env["SCENARIOS"].split(",")
        Scenario.all.select { |scenario| names.include?(scenario.name) }
      else Scenario.all(filter)
      end
    end
    private_class_method :scenarios_from

    # play: (scenario, recorder:, index:, rep:) → Runner::Result (tests pass their own).
    def initialize(scenarios:, runs:, out: $stdout, results_path: nil, notify: nil, draft: false, preflight: true,
                   outage: { after: 3, wait: 1800.0, poll: 15.0 }, filter: nil,
                   play: ->(scenario, **options) { Runner.new(scenario, **options).call })
      @scenarios = scenarios
      @runs = runs
      @out = out
      @results_path = results_path
      @notify = notify
      @draft = draft
      @preflight = preflight
      @outage = outage
      @filter = filter
      @play = play
      @results = []
    end

    def call
      raise NotStarted, "No scenarios match #{@filter.inspect}." if @scenarios.empty?

      check_the_model if @preflight
      @out.puts "Evaluating #{@scenarios.size} scenarios × #{@runs} with #{Assistant.model} (#{Assistant.provider}, " \
                "context #{Assistant.context_tokens || "unknown"}); everything is rolled back."
      start
      catch(:gave_up) { play_all }
      summarize
      finish
      path
    end

    private

    def check_the_model
      Preflight.check!(provider: Assistant.provider, model: Assistant.model)
    rescue Preflight::Unavailable => e
      raise NotStarted, "Not starting: #{e.message}. (EVAL_SKIP_PREFLIGHT=1 runs anyway; its turns will be scored as errors.)"
    end

    def path
      @path ||= begin
        dir = Rails.root.join("tmp/assistant_evals")
        FileUtils.mkdir_p(dir)
        default = dir.join("#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}-#{Assistant.model.tr(":/", "__")}.json")
        Pathname(@results_path || default).expand_path(Rails.root)
      end
    end

    def start
      @header = { model: Assistant.model, provider: Assistant.provider, runs: @runs, pid: Process.pid, started_at: Time.current.iso8601,
                  total: @scenarios.size * @runs, draft: @draft && @scenarios.first.name }
      save(finished: false)
      @recorder = Recorder.new(path.sub_ext(".events.jsonl"))
      plan = @scenarios.flat_map { |scenario| Array.new(@runs) { |i| { scenario: scenario.name, rep: i + 1 } } }
      @recorder.event("run_started", model: Assistant.model, provider: Assistant.provider, cases: plan)
    end

    # Rewritten whole after every result, through a rename: a reader never
    # sees half a file.
    def save(finished:)
      data = @header.merge(finished: finished, results: @results.map { |result| result.to_h.merge(turns: result.turns.map(&:to_h)) })
      File.write("#{path}.tmp", JSON.pretty_generate(data))
      File.rename("#{path}.tmp", path)
    end

    def play_all
      unreachable = 0
      @scenarios.each_with_index do |scenario, s|
        @runs.times do |i|
          result = @play.call(scenario, recorder: @recorder, index: (s * @runs) + i, rep: i + 1)
          report(scenario, i + 1, result)
          @results << result
          save(finished: false)

          unreachable = result.error_class == "unreachable" ? unreachable + 1 : 0
          next if unreachable < @outage[:after]

          wait_out_the_outage(unreachable)
          unreachable = 0
        end
      end
    end

    def report(scenario, rep, result)
      tools = result.turns.map { |turn| turn.tools.join(",").presence || "-" }.join(" | ")
      near = " ⚠ near context limit" if Assistant.near_context_limit?(result.max_step_input)
      @out.puts "#{MARKS.fetch(result.status)} #{scenario.name} ##{rep} #{result.seconds}s max_in=#{result.max_step_input}#{near} [#{tools}] " \
                "#{result.error || result.failures.first}"
    end

    def wait_out_the_outage(streak)
      left = @outage[:wait] - @header.fetch(:paused_for, 0)
      @out.puts "⏸ the model server was unreachable #{streak} times in a row — waiting for it (up to #{left.round}s)"
      @recorder.event("outage_started", streak: streak)
      waited = Outage.wait(limit: left, poll: @outage[:poll])
      if waited
        @header[:paused_for] = @header.fetch(:paused_for, 0) + waited.round
        @out.puts "▶ the model server is back after #{waited.round}s"
        @recorder.event("outage_ended", waited: waited.round)
      else
        @header[:gave_up] = true
        @out.puts "✗ the model server stayed unreachable for #{@outage[:wait].round}s — finishing with what was scored"
        @recorder.event("outage_ended", waited: nil, gave_up: true)
        throw :gave_up
      end
    end

    # Errors (the plumbing, not the model) are counted apart, never as failures.
    def summarize
      @out.puts "", "Pass rates:"
      @results.group_by(&:scenario).each { |name, list| @out.puts format("  %-36s %s", name, rate(list)) }
      @out.puts format("  %-36s %s", "TOTAL", rate(@results, total: true))
    end

    def rate(list, total: false)
      scored = list.reject { |result| result.status == "error" }
      errors = list.size - scored.size
      text = format("%d/%d", scored.count(&:passed), scored.size)
      text += " (#{(100.0 * scored.count(&:passed) / scored.size).round}%)" if total && scored.any?
      text += " · #{errors} not scored (errors)" if errors.positive?
      text += " · UNRELIABLE: #{errors} of #{list.size} not scored" if total && list.any? && errors.fdiv(list.size) > RunFile::UNRELIABLE_SHARE
      text
    end

    def finish
      save(finished: true)
      @recorder.event("run_finished", passed: @results.count(&:passed), errors: @results.count { |result| result.status == "error" },
                                      total: @results.size)
      @recorder.close
      tell_whoever_started_it
      @out.puts "", "Saved #{path.relative_path_from(Rails.root)}"
    end

    def tell_whoever_started_it
      starter = Profile.find_by(id: @notify) if @notify
      return if starter.nil?

      scored = @results.reject { |result| result.status == "error" }
      Notifications::Deliver.call(recipient: starter, kind: :eval_run_finished,
                                  data: { run_id: path.basename(".json").to_s, model: Assistant.model, passed: scored.count(&:passed), total: scored.size })
    end
  end
end
