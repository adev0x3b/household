# frozen_string_literal: true

require "test_helper"

class AssistantEval::RunFileTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname(Dir.mktmpdir)
    AssistantEval::RunFile.dir = @dir
  end

  teardown do
    AssistantEval::RunFile.dir = nil
    FileUtils.remove_entry(@dir)
  end

  def write(id, data) = @dir.join("#{id}.json").write(JSON.generate(data))

  def result(scenario, passed) = { scenario: scenario, passed: passed, failures: [], turns: [], seconds: 1.0, error: nil }

  def dead_pid
    pid = Process.spawn("true")
    Process.wait(pid)
    pid
  end

  test "a run reads as running while its process lives, crashed once it's gone, finished when marked" do
    write("20260926-100000-a", finished: false, pid: Process.pid, results: [])
    write("20260926-110000-b", finished: false, pid: dead_pid, results: [])
    write("20260926-120000-c", finished: true, pid: dead_pid, results: [])

    assert_equal :running, AssistantEval::RunFile.find("20260926-100000-a").status
    assert_equal :crashed, AssistantEval::RunFile.find("20260926-110000-b").status
    assert_equal :finished, AssistantEval::RunFile.find("20260926-120000-c").status
    assert_equal "20260926-100000-a", AssistantEval::RunFile.running.id
  end

  test "a stopped process reads as paused, not running, and still counts as active" do
    pid = Process.spawn("sleep", "30", pgroup: true)
    write("20260926-100000-p", finished: false, pid: pid, results: [])
    run = AssistantEval::RunFile.find("20260926-100000-p")
    assert_equal :running, run.status
    assert_predicate run, :active?

    Process.kill("STOP", pid)
    assert_eventually { run.status == :paused }
    assert_not run.running?
    assert_predicate run, :active?, "the poller keeps checking through a pause"

    Process.kill("CONT", pid)
    assert_eventually { run.status == :running }
  ensure
    Process.kill("KILL", pid)
    Process.wait(pid)
  end

  test "files written before live progress count as finished" do
    write("20260923-174410-qwen3-8b-household", model: "qwen3-8b-household", results: [ result("04", true) ])

    run = AssistantEval::RunFile.find("20260923-174410-qwen3-8b-household")
    assert_equal :finished, run.status
    assert_nil AssistantEval::RunFile.running
  end

  test "pass counts per scenario, newest runs first" do
    write("20260926-100000-old", finished: true, results: [])
    write("20260926-120000-new", finished: true, total: 3,
                                 results: [ result("04", true), result("04", false), result("05", true) ])

    run = AssistantEval::RunFile.recent.first
    assert_equal "20260926-120000-new", run.id
    assert_equal({ "04" => [ 1, 2, 0 ], "05" => [ 1, 1, 0 ] }, run.pass_counts)
    assert_equal [ 2, 3, 3 ], [ run.passed, run.done, run.total ]
  end

  test "errors are counted apart from failures, including old files' crashes" do
    write("20260927-120000-mixed", finished: true, results: [
            result("04", true).merge(status: "passed"),
            result("04", false).merge(status: "error", error: "the model server was unreachable"),
            result("05", false).merge(status: "failed"),
            result("05", false).merge(error: "RuntimeError: boom") # an old file: no status, an error was a crash
          ])

    run = AssistantEval::RunFile.find("20260927-120000-mixed")
    assert_equal [ 1, 2, 2 ], [ run.passed, run.scored, run.errors ]
    assert_equal({ "04" => [ 1, 1, 1 ], "05" => [ 0, 1, 1 ] }, run.pass_counts)
  end

  test "a pass rate comes with its noise, and only a change beyond it counts" do
    write("20260927-100000-a", finished: true, results: Array.new(27) { |i| result("04", i < 19) })
    write("20260927-110000-b", finished: true, results: Array.new(27) { |i| result("04", i < 21) })
    write("20260927-120000-c", finished: true, results: Array.new(27) { |i| result("04", i < 27) })
    a, b, c = %w[a b c].map { |x| AssistantEval::RunFile.find("20260927-#{{ "a" => "10", "b" => "11", "c" => "12" }[x]}0000-#{x}") }

    rate, low, high = a.pass_rate
    assert_in_delta 0.704, rate, 0.001
    assert_in_delta 0.515, low, 0.01
    assert_in_delta 0.841, high, 0.01
    assert_nil b.compared_to(a), "19 → 21 of 27 is inside the noise"
    assert_equal :up, c.compared_to(a)
    assert_equal :down, a.compared_to(c)
  end

  test "ids that aren't plain file names find nothing" do
    write("20260926-100000-a", finished: true, results: [])

    assert_nil AssistantEval::RunFile.find("../20260926-100000-a")
    assert_nil AssistantEval::RunFile.find("missing")
  end

  test "a run with too much unscored is unreliable; scenarios passing only sometimes are flaky" do
    write("20260927-130000-outage", finished: true, total: 10, paused_for: 600, gave_up: true, results: [
            result("04", true).merge(status: "passed"), result("04", false).merge(status: "failed"),
            *Array.new(3) { result("05", false).merge(status: "error", error: "the model server was unreachable") }
          ])
    write("20260927-140000-fine", finished: true, results: [ result("04", true), result("04", false), result("05", true), result("05", true) ])

    outage = AssistantEval::RunFile.find("20260927-130000-outage")
    assert_predicate outage, :unreliable?, "3 of 5 unscored"
    assert_predicate outage, :gave_up?
    assert_equal 600, outage.paused_for
    fine = AssistantEval::RunFile.find("20260927-140000-fine")
    assert_not fine.unreliable?
    assert_equal [ "04" ], fine.flaky_scenarios
    assert_equal 0, fine.paused_for
  end
end
