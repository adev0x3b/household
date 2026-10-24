# frozen_string_literal: true

# Tests an import against the assistant, beside English-only controls so
# that a failure is the language's and not the assistant's. What it plays and
# when it passes: docs/architecture/assistant.md, "The lexicon".
module Lexicon
  class AgentEval
    class Failure < StandardError; end
    # Stopped on request (cancelled: the import's cancel); its eval process is stopped too.
    class Cancelled < StandardError; end

    THRESHOLD = 0.8
    TOLERANCE = 0.15
    MAX_ERROR_SHARE = 0.5
    MIN_CASES = DictionaryCheck::MIN_CASES
    SEEDED = 200
    BOUGHT = 50
    DIR = Rails.root.join("tmp/lexicon_evals")
    POLL = 5
    BUSY_WAIT = 30.minutes

    # One kind of scenario a case is played as: what the user does (a dose
    # or a purchase), whose words name the supplies and whose the user
    # says (the language's or English). A scenario's name ends with its kind's.
    Kind = Data.define(:name, :action, :supplies, :words) do
      def dose? = action == :dose
      def native_supplies? = supplies == :native
      def english_words? = words == :english
      # English supplies and English words: nothing of the language, so what
      # fails here is the assistant's.
      def control? = supplies == :english && words == :english
      def to_s = name
    end

    KINDS = [
      Kind.new(name: "dose_native_supplies", action: :dose, supplies: :native, words: :english),
      Kind.new(name: "purchase_native_supplies", action: :purchase, supplies: :native, words: :english),
      Kind.new(name: "dose_english_supplies", action: :dose, supplies: :english, words: :native),
      Kind.new(name: "purchase_english_supplies", action: :purchase, supplies: :english, words: :native)
    ].freeze
    CONTROL_KINDS = [
      Kind.new(name: "control_dose", action: :dose, supplies: :english, words: :english),
      Kind.new(name: "control_purchase", action: :purchase, supplies: :english, words: :english)
    ].freeze
    ALL_KINDS = (KINDS + CONTROL_KINDS).freeze

    # The kind a scenario's name ends with; nil for a name of another run.
    def self.kind_of(scenario) = ALL_KINDS.find { scenario.to_s.end_with?("_#{_1.name}") }

    def self.control?(scenario) = kind_of(scenario)&.control? || false

    Summary = Data.define(:results, :review, :run_id) do
      def language_results = results.reject { AgentEval.control?(_1["scenario"]) }
      def control_results = results.select { AgentEval.control?(_1["scenario"]) }

      def tally(list)
        errors = list.count { _1["status"] == "error" }
        { passed: list.count { _1["status"] == "passed" }, scored: list.size - errors, errors: errors,
          wrong: list.count { |r| Array(r["failures"]).any? { _1.start_with?(AssistantEval::Checks::Untouched::WRONG_SUPPLY) } } }
      end

      def language = tally(language_results)
      def control = tally(control_results)
      def passed = language[:passed]
      def scored = language[:scored]
      def wrong = language[:wrong]
      def errors = language[:errors] + control[:errors]
      def total = results.size
      def rate = scored.zero? ? 0.0 : passed.fdiv(scored)
      def control_rate = control[:scored].zero? ? nil : control[:passed].fdiv(control[:scored])
      # What the language must reach: the controls' rate less TOLERANCE (THRESHOLD without controls).
      def bar = control_rate ? [ control_rate - TOLERANCE, 0.0 ].max : THRESHOLD
      def pass? = scored.positive? && wrong.zero? && rate >= bar && errors <= total * MAX_ERROR_SHARE

      def detail
        text = "#{passed}/#{scored} passed (#{(rate * 100).round}%)"
        text += " · English only #{control[:passed]}/#{control[:scored]} (#{(control_rate * 100).round}%)" if control_rate
        text += " · #{wrong} wrong supply"
        text += " · #{errors} not scored (errors)" if errors.positive?
        text
      end

      # Why it didn't pass, with the failing scenarios first.
      def problem
        reasons = []
        reasons << "#{wrong} run(s) touched a WRONG SUPPLY" if wrong.positive?
        if rate < bar
          reasons << (control_rate ? "#{(rate * 100).round}% passed, more than #{(TOLERANCE * 100).round} points under the English-only #{(control_rate * 100).round}%" :
                                     "#{(rate * 100).round}% passed, under #{(THRESHOLD * 100).round}%")
        end
        reasons << "#{errors} of #{total} runs were errors (the model or the harness)" if errors > total * MAX_ERROR_SHARE
        reasons << "nothing could be scored" if scored.zero?
        failing = language_results.reject { _1["status"] == "passed" }.first(5).map { |r| "#{r["scenario"]}: #{Array(r["failures"]).first || r["error"]} [#{r["tools"]}]" }
        "#{reasons.join("; ")}. #{failing.join(" · ")}"
      end

      def to_h = { "results" => results, "review" => review, "run_id" => run_id, "detail" => detail, "passed" => passed, "scored" => scored,
                   "wrong" => wrong, "errors" => errors, "control_rate" => control_rate, "finished_at" => Time.current.iso8601 }
    end

    # language: the Config::Language the import is for. cancelled: asked
    # whether to stop, while it waits. launcher / wait: tests.
    def initialize(import, language, on_progress: nil, cancelled: -> { false }, launcher: AssistantEval::Launcher,
                   wait: ->(seconds) { sleep(seconds) })
      @import = import
      @language = language
      @on_progress = on_progress
      @cancelled = cancelled
      @launcher = launcher
      @wait = wait
      @review = []
    end

    # nil when there's nothing to test with (the pivot and no translated language yet).
    def run
      targets = target_languages
      return if targets.empty?

      scenarios = targets.flat_map { |record| scenarios_for(record) }
      raise Failure, "no confirmed test case to play (#{@review.size} wait for review on the language's page)" if scenarios.empty?

      dir = write(scenarios)
      begin
        run_id = launch(dir)
        summarize(follow(run_id), run_id)
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    # The imports the eval process reads: this one in place of its language's active one.
    def imports = LexiconImport.active_ids.merge(@language.code => @import.id)

    # The language's scenarios and their English-only controls, from its confirmed cases.
    def scenarios_for(record)
      review = CaseReview.new(record.lexicon_eval_cases.order(:id).to_a, record, imports)
      counted, held = review.counted, review.waiting
      @review.concat(held.map { |kase, reason| { "language" => record.code, "concept" => kase.concept, "word" => kase.native_plural, "reason" => reason.to_s } })
      return [] if counted.empty? && @language.pivot?
      raise Failure, "#{record.wiktionary}: #{counted.size} confirmed test cases, at least #{MIN_CASES} are needed" if counted.size < MIN_CASES

      counted.each_with_index.flat_map do |kase, i|
        others = (counted.rotate(i + 1) - [ kase ]).first(2)
        ALL_KINDS.map { |kind| scenario(record, kase, others, kind) }
      end
    end

    private

    # The pivot has no words of its own to test: it is tested through every
    # translated language with an active import.
    def target_languages
      return [ LexiconLanguage.find_by!(code: @language.code) ] unless @language.pivot?

      active = LexiconImport.active_ids.keys
      LexiconLanguage.where(code: active, role: "translated").order(:code).to_a
    end

    def scenario(record, kase, others, kind)
      name_of = ->(c) { capitalize(kind.native_supplies? ? c.native_plural : english_plural(c)) }
      target = name_of.call(kase)
      supplies = ([ target ] + others.map(&name_of)).index_with { SEEDED }
      untouched = supplies.except(target)
      dose = kind.dose?
      said = if kind.english_words?
        dose ? EvalCases.dose_message(english_plural(kase)) : EvalCases.purchase_message(english_plural(kase))
      else
        dose ? kase.dose_sentence : kase.purchase_sentence
      end
      seed = [ { "supplies" => supplies } ]
      seed << { "dose_series" => { "name" => "Cobalamin", "day" => "monday" } } if dose
      expect = [ dose ? { "medication_details" => { "name" => "cobalamin", "uses" => { target => 1 } } } : { "stock" => { target => SEEDED + BOUGHT } },
                 { "supplies" => supplies.size }, { "untouched" => untouched } ]
      AssistantEval::Scenario.new(
        name: "#{record.code}_#{kase.concept.parameterize(separator: "_")}_#{kind}",
        description: "#{record.wiktionary} — #{kase.concept}: #{kind.name.tr("_", " ")} (supplies: #{supplies.keys.join(", ")})",
        today: Date.current, seed: seed, messages: [ said ], expect: expect, tags: [ "lexicon", record.code ]
      )
    end

    def english_plural(kase) = EvalCases.english_plural(kase)

    def capitalize(name) = name.to_s.sub(/\A\p{Ll}/) { _1.upcase }

    # A directory of its own: import ids repeat across databases (each test
    # process has one), and two runs must never share their scenario files.
    def write(scenarios)
      dir = DIR.join("#{@import.id}-#{SecureRandom.hex(4)}")
      FileUtils.mkdir_p(dir)
      scenarios.each { |s| File.write(dir.join("#{s.name}.yml"), s.to_yaml) }
      dir
    end

    def launch(dir)
      env = { "LEXICON_IMPORTS" => imports.map { "#{_1}=#{_2}" }.join(",") }
      deadline = Time.current + BUSY_WAIT
      begin
        @launcher.start!(scenario_dir: dir, runs: 1, env: env)
      rescue AssistantEval::Launcher::Busy
        raise Cancelled if @cancelled.call
        raise Failure, "the eval runner was busy with another run for #{BUSY_WAIT.inspect}" if Time.current > deadline

        @on_progress&.call("waiting for another eval run to finish")
        @wait.call(POLL * 6)
        retry
      rescue AssistantEval::Preflight::Unavailable => e
        raise Failure, "the model is unreachable: #{e.message}"
      end
    end

    def follow(run_id)
      loop do
        run = AssistantEval::RunFile.find(run_id) or raise Failure, "the eval run #{run_id} has no results file"
        if @cancelled.call
          @launcher.cancel!(run) if @launcher.respond_to?(:cancel!)
          raise Cancelled
        end
        @on_progress&.call(progress_text(run))
        return run if run.finished?
        raise Failure, "the eval process stopped early: #{run.log_tail.to_s.lines.last(3).join.squish.truncate(300)}" if run.status == :crashed

        @wait.call(POLL)
      end
    end

    # "12 of 40 runs · 11 passed · last: it_needle_dose_native_supplies ✓"
    def progress_text(run)
      last = run.results.last
      text = "#{run.done} of #{run.total} runs"
      text += " · #{run.passed} passed" if run.done.positive?
      text += " · last: #{last["scenario"]} #{AssistantEval::RunFile.status(last) == "passed" ? "✓" : "✗"}" if last
      text
    end

    def summarize(run, run_id)
      results = run.results.map do |result|
        { "scenario" => result["scenario"], "status" => AssistantEval::RunFile.status(result), "failures" => Array(result["failures"]),
          "error" => result["error"], "tools" => Array(result["turns"]).map { |t| Array(t["tools"]).join(",") }.join(" | ") }
      end
      Summary.new(results: results, review: @review, run_id: run_id)
    end
  end
end
