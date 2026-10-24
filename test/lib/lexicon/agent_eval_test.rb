# frozen_string_literal: true

require "test_helper"

# Lexicon::AgentEval: the scenarios it builds from a language's cases, the
# cases it sets aside for review, and how it runs them (the launcher and
# its results file stand in for the eval process and the model).
class Lexicon::AgentEvalTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 3, 12)
    import_lexicons
    @italian = LexiconLanguage.find_by!(code: "it")
    @italian.lexicon_eval_cases.where.not(concept: %w[needle syringe plaster]).delete_all # the builders' glove: three cases here
    @italian.lexicon_eval_cases.create!(concept: "gauze", native_singular: "gause", native_plural: "gause", confirmed: false,
                                        dose_sentence: "uso gause", purchase_sentence: "ho comprato gause")
    @import = LexiconImport.active_for("it")
    @runs = Dir.mktmpdir
    AssistantEval::RunFile.dir = @runs
  end

  teardown do
    travel_back
    AssistantEval::RunFile.dir = nil
    FileUtils.rm_rf(@runs)
  end

  def eval_for(import = @import, language: Lexicon::Config.fetch("it"), launcher: nil)
    Lexicon::AgentEval.new(import, language, launcher: launcher || finished_launcher, wait: ->(_) { })
  end

  # Writes a finished run whose every scenario passed, except those named in `failing`.
  def finished_launcher(failing: {})
    dir = @runs
    Object.new.tap do |launcher|
      launcher.define_singleton_method(:start!) do |scenario_dir:, env:, **|
        @env = env
        names = Dir[File.join(scenario_dir, "*.yml")].map { File.basename(_1, ".yml") }.sort
        results = names.map do |name|
          failures = Array(failing[name])
          { scenario: name, passed: failures.empty?, status: failures.empty? ? "passed" : "failed", failures: failures,
            turns: [ { tools: [ "update_record" ] } ] }
        end
        File.write(File.join(dir, "run1.json"), JSON.generate(finished: true, total: results.size, results: results))
        "run1"
      end
      launcher.define_singleton_method(:env) { @env }
    end
  end

  test "six scenarios per confirmed case — four with the language, two English-only controls" do
    scenarios = eval_for.scenarios_for(@italian)

    assert_equal 18, scenarios.size, "needle, syringe, plaster × 6 — gauze isn't confirmed"
    assert_equal(Lexicon::AgentEval::ALL_KINDS.map(&:name), scenarios.first(6).map { _1.name.delete_prefix("it_needle_") })
  end

  test "the controls: English supplies, English words — no translation at all" do
    control = eval_for.scenarios_for(@italian).index_by(&:name).fetch("it_needle_control_dose")

    assert_equal({ "Needles" => 200, "Syringes" => 200, "Plasters" => 200 }, control.seed.first["supplies"])
    assert_equal [ "For my cobalamin injections I use needles: 1 per dose, from now on." ], control.messages
  end

  test "only confirmed cases count; the others wait with a hint, and a confirmed duplicate is set aside" do
    @italian.lexicon_eval_cases.create!(concept: "glove", native_singular: "lancetta", native_plural: "lancette", confirmed: false,
                                        dose_sentence: "uso lancette", purchase_sentence: "ho comprato lancette")
    @italian.lexicon_eval_cases.create!(concept: "vial", native_singular: "ago", native_plural: "aghi", confirmed: true,
                                        dose_sentence: "uso aghi", purchase_sentence: "ho comprato aghi")
    reasons = eval_for.run.review.to_h { [ _1["concept"], _1["reason"] ] }

    assert_equal({ "gauze" => "not_in_dictionary", "glove" => "unlinked", "vial" => "duplicate" }, reasons.slice("gauze", "glove", "vial"))

    @italian.lexicon_eval_cases.find_by!(concept: "glove").update!(confirmed: true)
    confirmed = eval_for.scenarios_for(@italian).map(&:name)
    assert_includes confirmed, "it_glove_dose_native_supplies", "confirmed by a person: a dictionary gap now fails the test"
  end

  test "each scenario seeds the meant supply among two others, and checks they stay untouched" do
    scenarios = eval_for.scenarios_for(@italian).index_by(&:name)
    dose = scenarios.fetch("it_needle_dose_english_supplies")
    purchase = scenarios.fetch("it_needle_purchase_native_supplies")

    assert_equal({ "Needles" => 200, "Syringes" => 200, "Plasters" => 200 }, dose.seed.first["supplies"])
    assert_equal [ "Per le mie iniezioni di cobalamina uso aghi: 1 per dose, da ora in poi." ], dose.messages
    assert_includes dose.expect, { "untouched" => { "Syringes" => 200, "Plasters" => 200 } }
    assert_equal [ "I bought needles: 50 pieces, 10 euros, paid by card." ], purchase.messages
    assert_includes purchase.expect, { "stock" => { "Aghi" => 250 } }
  end

  test "no generated scenario passes for an agent that does nothing" do
    scenarios = eval_for.scenarios_for(@italian)

    assert(scenarios.none? { AssistantEval::NullBaseline.lenient?(_1) })
  end

  test "a run: the import in place of the active one, every result kept, the review list" do
    launcher = finished_launcher(failing: { "it_needle_dose_english_supplies" => [ "medication_details: uses aghi 0.0" ] })
    summary = eval_for(launcher: launcher).run

    assert_equal("it=#{@import.id}", launcher.env["LEXICON_IMPORTS"].split(",").find { _1.start_with?("it=") })
    assert_equal [ 11, 12, 0 ], [ summary.passed, summary.scored, summary.wrong ]
    assert_in_delta(1.0, summary.control_rate, 0.001, "6 English-only runs, all passed")
    assert_predicate summary, :pass?, "92% is within 15 points of the controls' 100%"
    assert_equal([ "gauze" ], summary.review.map { _1["concept"] })
  end

  test "a language as good as the controls passes even when both miss" do
    failing = %w[needle syringe plaster].flat_map { |c| [ "it_#{c}_dose_native_supplies", "it_#{c}_control_dose" ] }.index_with { [ "medication_details: uses x 0.0" ] }
    summary = eval_for(launcher: finished_launcher(failing: failing)).run

    assert_equal [ 9, 12 ], [ summary.passed, summary.scored ]
    assert_in_delta(0.5, summary.control_rate)
    assert_predicate summary, :pass?, "the dose habit is the assistant's: it fails in English too"
    assert_equal([ "gauze" ], summary.review.map { _1["concept"] })
  end

  test "a wrong supply is counted apart and fails the run" do
    summary = eval_for(launcher: finished_launcher(failing: { "it_syringe_purchase_native_supplies" => [ "WRONG SUPPLY: Aghi stock 250.0≠200" ] })).run

    assert_equal 1, summary.wrong
    assert_not summary.pass?
    assert_match "WRONG SUPPLY", summary.problem
  end

  test "a run where nothing could be scored fails, and says so" do
    results = [ { "scenario" => "it_needle_dose_native_supplies", "status" => "error", "failures" => [], "error" => "timeout", "tools" => "" } ]
    summary = Lexicon::AgentEval::Summary.new(results: results, review: [], run_id: "run1")

    assert_in_delta 0.0, summary.rate
    assert_not summary.pass?
    assert_match "nothing could be scored", summary.problem
  end

  test "a language with fewer confirmed cases than a test needs is a failure that says how many" do
    @italian.lexicon_eval_cases.find_by!(concept: "plaster").destroy!

    error = assert_raises(Lexicon::AgentEval::Failure) { eval_for.run }
    assert_match "Italian: 2 confirmed test cases, at least 3 are needed", error.message
  end

  test "the pivot with no confirmed case in any translated language has nothing to play, and says what waits for review" do
    @italian.lexicon_eval_cases.where(confirmed: true).delete_all

    error = assert_raises(Lexicon::AgentEval::Failure) { eval_for(LexiconImport.active_for("en"), language: Lexicon::Config.fetch("en")).run }
    assert_match "no confirmed test case to play (1 wait for review on the language's page)", error.message
  end

  test "the pivot with no translated language active yet is not tested" do
    @import.superseded!

    assert_nil eval_for(LexiconImport.active_for("en"), language: Lexicon::Config.fetch("en")).run
  end

  test "an unreachable model is a failure that names it" do
    launcher = Object.new.tap { _1.define_singleton_method(:start!) { |**| raise AssistantEval::Preflight::Unavailable, "ollama.local is offline" } }

    error = assert_raises(Lexicon::AgentEval::Failure) { eval_for(launcher: launcher).run }
    assert_match "the model is unreachable: ollama.local is offline", error.message
  end

  def agent_eval(launcher, **options) = Lexicon::AgentEval.new(@import, Lexicon::Config.fetch("it"), launcher: launcher, wait: ->(_) { }, **options)

  test "a busy eval runner is waited for, and said; busy too long, or cancelled meanwhile, it stops" do
    attempts = 0
    then_done = finished_launcher
    busy_once = Object.new.tap { |l| l.define_singleton_method(:start!) { |**run| (attempts += 1) == 1 ? raise(AssistantEval::Launcher::Busy) : then_done.start!(**run) } }
    said = []
    agent_eval(busy_once, on_progress: ->(text) { said << text }).run
    assert_includes said, "waiting for another eval run to finish"
    assert_equal 2, attempts

    always_busy = Object.new.tap { _1.define_singleton_method(:start!) { |**| raise AssistantEval::Launcher::Busy } }
    error = assert_raises(Lexicon::AgentEval::Failure) { agent_eval(always_busy, wait: ->(seconds) { travel(seconds) }).run }
    assert_match "busy with another run", error.message
    assert_raises(Lexicon::AgentEval::Cancelled) { agent_eval(always_busy, cancelled: -> { true }).run }
  end

  test "a run is followed until it ends, said as it goes; one whose process died fails with its log's end; a cancel stops it" do
    dir = @runs
    write = ->(pid, results) { File.write(File.join(dir, "run1.json"), JSON.generate(finished: false, pid: pid, total: 6, results: results)) }
    first = [ { scenario: "it_needle_dose_native_supplies", passed: true, status: "passed" } ]
    then_done = finished_launcher
    going = Object.new.tap do |launcher|
      # This process stands for the eval's while it runs; finish! ends it.
      launcher.define_singleton_method(:start!) { |scenario_dir:, **| (@dir = scenario_dir) && write.call(Process.pid, first) && "run1" }
      launcher.define_singleton_method(:finish!) { then_done.start!(scenario_dir: @dir, runs: 1, env: {}) }
      launcher.define_singleton_method(:cancel!) { |run| @cancelled = run.id }
      launcher.define_singleton_method(:cancelled) { @cancelled }
    end
    said = []
    agent_eval(going, on_progress: ->(text) { said << text }, wait: ->(_) { going.finish! }).run
    assert_includes said, "1 of 6 runs · 1 passed · last: it_needle_dose_native_supplies ✓"

    dead = Process.spawn("true").tap { Process.wait(_1) }
    gone = Object.new.tap { |l| l.define_singleton_method(:start!) { |**| write.call(dead, []) && "run1" } }
    File.write(File.join(dir, "run1.log"), "starting\nthe model said no\nTraceback: boom\n")
    error = assert_raises(Lexicon::AgentEval::Failure) { agent_eval(gone).run }
    assert_match "stopped early: starting the model said no Traceback: boom", error.message

    assert_raises(Lexicon::AgentEval::Cancelled) { agent_eval(going, cancelled: -> { going.cancelled.nil? && File.exist?(File.join(dir, "run1.json")) }).run }
    assert_equal "run1", going.cancelled
  end

  test "a run with no result yet says how many are coming; a launcher that can't cancel is still stopped" do
    dir = @runs
    then_done = finished_launcher
    starting = Object.new.tap do |launcher|
      launcher.define_singleton_method(:start!) do |scenario_dir:, **|
        @dir = scenario_dir
        File.write(File.join(dir, "run1.json"), JSON.generate(finished: false, pid: Process.pid, total: 18, results: []))
        "run1"
      end
      launcher.define_singleton_method(:finish!) { then_done.start!(scenario_dir: @dir, runs: 1, env: {}) }
    end
    said = []
    agent_eval(starting, on_progress: ->(text) { said << text }, wait: ->(_) { starting.finish! }).run
    assert_equal "0 of 18 runs", said.first

    assert_raises(Lexicon::AgentEval::Cancelled) { agent_eval(starting, cancelled: -> { File.exist?(File.join(dir, "run1.json")) }).run }
  end

  test "the pivot is tested through every translated language with an active import" do
    english = LexiconImport.active_for("en")
    summary = eval_for(english, language: Lexicon::Config.fetch("en")).run

    assert_equal 12, summary.scored, "the Italian cases, with English's import as the candidate"
  end

  # ── passable: what a good agent does, through the real tools ──

  def replay(scenario)
    profile = AssistantEval::Sandbox.profile!
    AssistantEval::Seeds.apply(scenario.seed, profile)
    yield assistant_chat(profile)
    AssistantEval::Expectations.new(profile).failures(scenario.expect)
  end

  test "passable: Italian words for English supplies, and English words for Italian ones" do
    scenarios = eval_for.scenarios_for(@italian).index_by(&:name)

    assert_empty(replay(scenarios.fetch("it_needle_dose_english_supplies")) do |chat|
      run_tool(:update_record, chat, type: "medication", ref: "cobalamin", uses: [ { supply: "aghi", quantity: 1 } ])
    end)
    assert_empty(replay(scenarios.fetch("it_needle_purchase_native_supplies")) do |chat|
      run_tool(:record_purchases, chat, payment_method: "card", items: [ { supply: "needles", quantity: 50, amount: 10 } ])
    end)
  end

  test "the untouched check calls a used distractor a WRONG SUPPLY" do
    scenario = eval_for.scenarios_for(@italian).index_by(&:name).fetch("it_needle_dose_english_supplies")
    failures = replay(scenario) do |chat|
      run_tool(:update_record, chat, type: "medication", ref: "cobalamin", uses: [ { supply: "Syringes", quantity: 1 } ])
    end

    assert(failures.any? { _1.start_with?("WRONG SUPPLY: Syringes is used by a dose") }, failures.inspect)
  end
end
