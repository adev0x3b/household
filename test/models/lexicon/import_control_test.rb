# frozen_string_literal: true

require "test_helper"

# An import can be stopped, and one whose job never ran never blocks the
# next: LexiconImport#cancel!, #live?, #enqueue!, and the import noticing a
# cancel between steps and during its assistant test.
class Lexicon::ImportControlTest < ActiveSupport::TestCase
  test "asked to stop before it starts, it ends cancelled at its first step, nothing loaded" do
    import = LexiconImport.create!(language: "it", status: :running, started_at: Time.current, report: Lexicon::Import.initial_report,
                                   cancel_requested_at: Time.current)
    italian_cases!
    Lexicon::Import.call(lexicon_language("it"), import: import, source: file_fixture("lexicon/italian_sample.jsonl.gz").to_s,
                                                 force: true, agent: :skip)

    assert_predicate import.reload, :cancelled?
    assert_equal "configure", import.failed_step
    assert_equal [ "cancelled" ], import.steps.map { _1["status"] }.uniq - [ "skipped" ]
  end

  test "a cancel during the assistant test stops it there, its rows deleted, the active import kept" do
    active = import_lexicon("it")
    cancelling = lambda do |import, _language, progress|
      import.update!(cancel_requested_at: Time.current)
      progress.call("3 of 20 runs")
    end
    import = import_lexicon("it", agent: cancelling)

    assert_predicate import, :cancelled?, import.inspect
    assert_equal "agent", import.failed_step
    assert_equal "cancelled", import.steps.find { _1["name"] == "agent" }["status"]
    assert_equal 0, LexiconLemma.where(lexicon_import_id: import.id).count
    assert_predicate active.reload, :active?
  end

  test "the assistant test stops its eval process when cancelled" do
    import = import_lexicon("it")
    runs = Dir.mktmpdir
    AssistantEval::RunFile.dir = runs
    launcher = Object.new
    launcher.define_singleton_method(:start!) do |**|
      File.write(File.join(runs, "r1.json"), JSON.generate(finished: false, total: 24, results: [], pid: Process.pid))
      "r1"
    end
    launcher.define_singleton_method(:cancel!) { |run| @cancelled = run.id }
    launcher.define_singleton_method(:cancelled) { @cancelled }

    assert_raises(Lexicon::AgentEval::Cancelled) do
      Lexicon::AgentEval.new(import, Lexicon::Config.fetch("it"), launcher: launcher, wait: ->(_) { }, cancelled: -> { true }).run
    end
    assert_equal "r1", launcher.cancelled
  ensure
    AssistantEval::RunFile.dir = nil
  end

  test "cancel!: one waiting for review stops now and lets go of what it kept" do
    italian_cases!(confirmed: false)
    import = import_lexicon("it")
    assert_predicate import, :awaiting_review?

    assert_equal :cancelled, import.cancel!
    assert_predicate import.reload, :cancelled?
    assert_equal "cancelled", import.steps.find { _1["name"] == "dictionary" }["status"]
    assert_not LexiconLemma.exists?(lexicon_import_id: import.id)
  end

  test "cancel!: one being worked is asked to stop; one whose job never came stops now" do
    working = LexiconImport.create!(language: "it", status: :running, started_at: Time.current, report: Lexicon::Import.initial_report)
    assert_equal :stopping, working.cancel!
    assert working.reload.cancel_requested_at

    orphan = LexiconImport.create!(language: "es", status: :running, started_at: 4.hours.ago, created_at: 4.hours.ago,
                                   updated_at: 4.hours.ago, report: Lexicon::Import.initial_report)
    assert_not orphan.live?, "no job, nothing heard for hours"
    assert_equal :cancelled, orphan.cancel!
    assert_predicate orphan.reload, :cancelled?
  end

  test "an import whose job never came doesn't block the next one" do
    LexiconImport.create!(language: "it", status: :running, started_at: 4.hours.ago, created_at: 4.hours.ago, updated_at: 4.hours.ago,
                          report: Lexicon::Import.initial_report)

    assert_nil LexiconImport.live_for("it")
    assert_predicate import_lexicon("it"), :active?
  end

  test "enqueue!: a job that can't be queued fails the import at once, saying why" do
    import = LexiconImport.create!(language: "it", status: :running, started_at: Time.current, report: Lexicon::Import.initial_report)

    swapping(Lexicon::ImportJob, :perform_later, ->(*, **) { raise ActiveRecord::StatementInvalid, "relation \"solid_queue_jobs\" does not exist" }) do
      assert_not import.enqueue!(download: true)
    end
    assert_predicate import.reload, :failed?
    assert_match "its job couldn't be queued", import.error
    assert_match "solid_queue_jobs", import.error
  end

  test "a job for an import cancelled while it waited does nothing" do
    import = LexiconImport.create!(language: "it", status: :cancelled, report: Lexicon::Import.initial_report)

    Lexicon::ImportJob.perform_now(import.id)
    assert_predicate import.reload, :cancelled?
  end
end
