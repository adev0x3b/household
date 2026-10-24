# frozen_string_literal: true

require "test_helper"

# Lexicon::Import: every step reports ✓/✗, a failure names its step and
# what broke, and a failed import never replaces the active one.
class Lexicon::ImportTest < ActiveSupport::TestCase
  def step(import, name) = import.steps.find { _1["name"] == name }
  def statuses(import) = import.steps.to_h { [ _1["name"], _1["status"] ] }

  def assert_failed_at(import, step_name, message)
    assert_predicate import, :failed?, import.inspect
    assert_equal step_name, import.failed_step
    assert_match message, import.error
    assert_equal "failed", step(import, step_name)["status"]
    later = Lexicon::Import::STEPS.drop(Lexicon::Import::STEPS.index(step_name) + 1)
    assert_equal [ "skipped" ], later.map { statuses(import)[_1] }.uniq if later.any?
    assert_equal 0, LexiconLemma.where(lexicon_import_id: import.id).count, "a failed import's rows are deleted"
  end

  test "a good import: every step ✓, every check recorded, the language active" do
    import = import_lexicon("it")

    assert_predicate import, :active?, import.error
    assert_equal [ "ok" ], statuses(import).except("agent").values.uniq
    assert_match "AGENT=skip", step(import, "agent")["detail"], "tests skip the model; skipping is always written down"
    assert_match "nouns kept, 0 malformed", step(import, "parse")["detail"]
    assert import.checks.all? { _1["ok"] }, import.checks.inspect
    assert_equal import, LexiconImport.active_for("it")
    assert_operator import.lemma_count, :>, 10
  end

  test "a new import replaces the active one, whose rows go" do
    first = import_lexicon("it")
    second = import_lexicon("it")

    assert_predicate second, :active?
    assert_predicate first.reload, :superseded?
    assert_equal 0, LexiconLemma.where(lexicon_import_id: first.id).count
  end

  test "configure: an incomplete language never starts" do
    import = import_lexicon("it", head: "middle", checks: [ Lexicon::Config::Check.new(spec: { "form" => "TODO", "lemma" => "x" }) ])

    assert_failed_at import, "configure", /head: must be one of first, last.*still TODO/
  end

  test "source: a missing extract is named with where it was looked for" do
    import = import_lexicon("it", source: "/nonexistent/italian.jsonl.gz")

    assert_failed_at import, "source", "no such file: /nonexistent/italian.jsonl.gz"
  end

  test "an extract unchanged since the active import is left alone, not failed" do
    import_lexicon("it")
    import = Lexicon::Import.call(lexicon_language("it"), source: LexiconBuilders::LEXICON_FIXTURES.join("italian_sample.jsonl.gz").to_s)

    assert_predicate import, :unchanged?
    assert_match "unchanged since the active import", step(import, "source")["detail"]
    assert_equal "skipped", step(import, "download")["status"]
  end

  test "download: a truncated file fails as a broken download, and the active import stays" do
    active = import_lexicon("it")
    whole = File.binread(LexiconBuilders::LEXICON_FIXTURES.join("italian_sample.jsonl.gz"))
    cut = Tempfile.new([ "cut", ".jsonl.gz" ]).tap { _1.binmode.write(whole[0, whole.size / 2]) && _1.flush }
    import = import_lexicon("it", source: cut.path)

    assert_failed_at import, "download", "ended early"
    assert_predicate active.reload, :active?
    assert_equal "Aghi", Lexicon::Matcher.new.pick(%w[Aghi Siringhe], "needle").name, "matching still uses the active import"
  end

  test "download: a file that isn't gzip says so" do
    plain = Tempfile.new([ "plain", ".jsonl.gz" ]).tap { _1.write("{\"pos\": \"noun\"}\n") && _1.flush }

    assert_failed_at import_lexicon("it", source: plain.path), "download", "gzip"
  end

  test "parse: too many malformed lines fail with the first one's line number" do
    lines = sample_lines("it") + Array.new(5) { |i| "{\"pos\": \"noun\", \"word\": \"broken#{i}\", " }

    assert_failed_at import_lexicon("it", source: gzip_lines(lines).path), "parse", /not valid JSON .* first at line \d+/
  end

  test "parse: a file without nouns isn't taken for an extract" do
    lines = sample_lines("it").reject { _1.include?("\"noun\"") }

    assert_failed_at import_lexicon("it", source: gzip_lines(lines).path), "parse", "no nouns"
  end

  test "verify: a failing check names the check and what was found, and the active import stays" do
    active = import_lexicon("it")
    checks = Lexicon::Config.fetch("it").checks + [ Lexicon::Config::Check.new(spec: { "word" => "ago", "means" => "fork" }) ]
    import = import_lexicon("it", checks: checks)

    assert_failed_at import, "verify", "1 of 8 checks failed: word: ago · means: fork (got needle"
    assert_equal false, import.checks.last["ok"]
    assert_predicate active.reload, :active?
  end

  test "verify: fewer nouns than min_lemmas is a broken extract" do
    assert_failed_at import_lexicon("it", min_lemmas: 1_000_000), "verify", "fewer than min_lemmas"
  end

  test "verify: an import much smaller than the active one never replaces it" do
    import_lexicon("it")
    few = sample_lines("it").select { _1.include?("\"word\": \"ago\"") || _1.include?("\"word\": \"siringa\"") || _1.include?("\"word\": \"cerotto\"") }

    assert_failed_at import_lexicon("it", source: gzip_lines(few).path), "verify", "kept the active one"
  end

  test "configure: a second import of a language while one runs is refused" do
    running = LexiconImport.create!(language: "it", status: :running, started_at: 1.minute.ago)

    assert_failed_at import_lexicon("it"), "configure", "another import of it is running (##{running.id})"
  end

  test "the pivot keeps two-way synonyms only" do
    import_lexicon("en")
    vial = LexiconLemma.find_by!(key: "vial", lexicon_import: LexiconImport.active_for("en"))
    synonyms = vial.lexicon_meanings.synonym.pluck(:key)

    assert_includes synonyms, "phial"
    assert_not_includes synonyms, "jar", "vial lists jar, jar doesn't list vial"
  end

  # ── dictionary: the confirmed test cases, matched with no model ──

  test "dictionary: the confirmed cases are matched both ways, every pick recorded" do
    import = import_lexicon("it")

    assert_predicate import, :active?, import.error
    assert_match(/\A16\/16 picked right, 0 wrong, 0 not found\z/, step(import, "dictionary")["detail"])
    assert_equal 16, import.report.dig("dictionary", "results").size, "4 cases × (2 words to English + 2 English words)"
  end

  test "dictionary: a confirmed word the dictionary can't place fails it, naming the word" do
    italian_cases!.lexicon_eval_cases.find_by!(concept: "glove").update!(native_singular: "lancetta", native_plural: "lancette")
    import = import_lexicon("it")

    assert_failed_at import, "dictionary", "“lancette” → nothing (expected Gloves)"
  end

  test "dictionary: too few confirmed cases — the import waits for review, its rows kept, and Continue finishes it" do
    italian_cases!(confirmed: false)
    import = import_lexicon("it")

    assert_predicate import, :awaiting_review?, import.inspect
    assert_equal "waiting", step(import, "dictionary")["status"]
    assert_match "0 of 4 test cases are confirmed", step(import, "dictionary")["detail"]
    assert LexiconLemma.exists?(lexicon_import_id: import.id), "kept for the review"
    assert_nil LexiconImport.active_for("it")

    LexiconLanguage.find_by!(code: "it").lexicon_eval_cases.update_all(confirmed: true)
    resumed = Lexicon::Import.call("it", import: import.reload, resume: true, agent: :skip)

    assert_predicate resumed, :active?, resumed.error
    assert_equal "ok", step(resumed, "dictionary")["status"]
  end

  test "dictionary: a language with no test cases yet has the model draft them, then waits for their review" do
    drafted = lambda do |language|
      LexiconBuilders::ITALIAN_CASES.map do |concept, (one, many)|
        language.lexicon_eval_cases.create!(concept: concept, native_singular: one, native_plural: many,
                                            dose_sentence: "uso #{many}", purchase_sentence: "ho comprato #{many}")
      end
    end
    import = swapping(Lexicon::EvalCases, :generate!, drafted) { import_lexicon("it", cases: false) }

    assert_predicate import, :awaiting_review?, import.inspect
    assert_match "0 of 4 test cases are confirmed", step(import, "dictionary")["detail"]
  end

  test "dictionary: when the model can't draft the cases, the import waits saying so" do
    failing = ->(_language) { raise Lexicon::EvalCases::Error, "the model didn't answer" }
    import = swapping(Lexicon::EvalCases, :generate!, failing) { import_lexicon("it", cases: false) }

    assert_predicate import, :awaiting_review?, import.inspect
    assert_match "couldn't write the test cases (the model didn't answer)", step(import, "dictionary")["detail"]
  end

  test "only an import waiting for review goes on; asking another to leaves it as it was" do
    import = import_lexicon("it")

    error = assert_raises(ArgumentError) { Lexicon::Import.call("it", import: import, resume: true, agent: :skip) }
    assert_match "(active)", error.message
    assert_predicate import.reload, :active?
    assert_raises(ArgumentError) { Lexicon::Import.call("it", resume: true) }
  end

  test "a bug mid-import is reported and fails the import at the step it was in" do
    bug = ->(*) { raise "a bug in the agent step" }
    import = nil

    assert_error_reported(RuntimeError) { import = import_lexicon("it", agent: bug) }
    assert_failed_at import, "agent", "unexpected RuntimeError: a bug in the agent step"
  end

  test "an import waiting for review is replaced by the next one that activates" do
    italian_cases!(confirmed: false)
    waiting = import_lexicon("it")
    LexiconLanguage.find_by!(code: "it").lexicon_eval_cases.update_all(confirmed: true)
    import_lexicon("it")

    assert_predicate waiting.reload, :superseded?
    assert_not LexiconLemma.exists?(lexicon_import_id: waiting.id)
  end

  # ── agent: the import tested against the assistant (Lexicon::AgentEval) ──

  # Results for `language` runs (passed first, then failed, then errors) and
  # `control` English-only runs (passed first).
  def summary(passed:, scored: 20, errors: 0, wrong: 0, control_passed: nil, control: 10)
    results = Array.new(scored + errors) do |i|
      status = if i < passed then "passed" elsif i < scored then "failed" else "error" end
      failures = status == "failed" ? [ i == passed && wrong.positive? ? "WRONG SUPPLY: Siringhe stock 150.0≠200" : "stock: Aghi 200.0≠250" ] : []
      { "scenario" => "it_needle_case_#{i}", "status" => status, "failures" => failures, "error" => nil, "tools" => "record_purchases" }
    end
    if control_passed
      results += Array.new(control) do |i|
        { "scenario" => "it_needle_#{i}_control_dose", "status" => i < control_passed ? "passed" : "failed",
          "failures" => i < control_passed ? [] : [ "medication_details: uses Needles 0.0" ], "error" => nil, "tools" => "record_purchases" }
      end
    end
    Lexicon::AgentEval::Summary.new(results: results, review: [], run_id: "run")
  end

  def agent_returning(result)
    lambda do |_import, _language, progress|
      progress.call("3 of 20 runs")
      result
    end
  end

  test "agent: as good as English alone activates it, with both rates and every result kept" do
    import = import_lexicon("it", agent: agent_returning(summary(passed: 14, control_passed: 7)))

    assert_predicate import, :active?, import.error
    assert_equal "14/20 passed (70%) · English only 7/10 (70%) · 0 wrong supply", step(import, "agent")["detail"]
    assert_equal 30, import.report.dig("agent", "results").size
  end

  test "agent: far under English alone fails, naming the failing scenarios, and the active import stays" do
    active = import_lexicon("it")
    import = import_lexicon("it", agent: agent_returning(summary(passed: 10, control_passed: 9)))

    assert_failed_at import, "agent", /50% passed, more than 15 points under the English-only 90%\. it_needle_case_10: stock: Aghi 200.0≠250 \[record_purchases\]/
    assert_predicate active.reload, :active?
  end

  test "agent: without English-only runs to compare with, 80% is the bar" do
    assert_failed_at import_lexicon("it", agent: agent_returning(summary(passed: 14))), "agent", "70% passed, under 80%"
  end

  test "agent: one wrong supply fails it however high the pass rate" do
    import = import_lexicon("it", agent: agent_returning(summary(passed: 19, wrong: 1, control_passed: 10)))

    assert_failed_at import, "agent", "1 run(s) touched a WRONG SUPPLY"
  end

  test "agent: mostly errors (the model, not the dictionary) is no verdict" do
    import = import_lexicon("it", agent: agent_returning(summary(passed: 4, scored: 4, errors: 16)))

    assert_failed_at import, "agent", "16 of 20 runs were errors"
  end

  test "agent: an unreachable model stops the import there, keeping the active one" do
    active = import_lexicon("it")
    unreachable = ->(*) { raise Lexicon::AgentEval::Failure, "the model is unreachable: ollama.local is offline" }

    assert_failed_at import_lexicon("it", agent: unreachable), "agent", "the model is unreachable"
    assert_predicate active.reload, :active?
  end

  test "agent: the pivot with no translated language to test against is skipped, not failed" do
    import = import_lexicon("en", agent: ->(*) { nil })

    assert_predicate import, :active?
    assert_equal "skipped", step(import, "agent")["status"]
    assert_equal "skipped", step(import, "dictionary")["status"]
  end
end
