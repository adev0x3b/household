# frozen_string_literal: true

require "test_helper"

class AssistantEval::LauncherTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname(Dir.mktmpdir)
    AssistantEval::RunFile.dir = @dir
    @spawned = []
  end

  teardown do
    AssistantEval::RunFile.dir = nil
    FileUtils.remove_entry(@dir)
  end

  # No real process: records what would have been spawned. The fake pid is
  # this test process, so the run counts as alive afterwards.
  def launching(&)
    spawned = @spawned # the lambda runs with self = Process
    spawn = lambda do |env, *command, **options|
      spawned << { env: env, command: command, options: options }
      Process.pid
    end
    swapping(AssistantEval::Preflight, :check!, ->(**) { true }) do
      swapping(Process, :spawn, spawn) { swapping(Process, :detach, ->(_pid) { nil }, &) }
    end
  end

  test "a model that isn't there stops the run before anything is spawned" do
    offline = ->(**) { raise AssistantEval::Preflight::Unavailable, "the Ollama server isn't answering" }
    swapping(AssistantEval::Preflight, :check!, offline) do
      swapping(Process, :spawn, ->(*) { flunk "spawned" }) do
        assert_raises(AssistantEval::Preflight::Unavailable) { AssistantEval::Launcher.start!(provider: "ollama", model: "qwen3-8b-household") }
      end
    end
    assert_empty Dir[@dir.join("*.json")]
  end

  test "starts the eval task as its own process, with the run's settings in the environment" do
    id = launching { AssistantEval::Launcher.start!(scenarios: %w[04_lab_report_alone 05_lab_report_with_ranges], runs: 99, provider: "anthropic", model: "claude-haiku-4-5-20251001") }

    spawn = @spawned.sole
    assert_equal [ Rails.root.join("bin/rails").to_s, "assistant:eval[10]" ], spawn[:command], "argv, no shell string; runs capped"
    assert_equal "04_lab_report_alone,05_lab_report_with_ranges", spawn[:env]["SCENARIOS"]
    assert_equal "anthropic", spawn[:env]["EVAL_PROVIDER"], "the run's own provider, over the saved settings"
    assert_equal "claude-haiku-4-5-20251001", spawn[:env]["EVAL_MODEL"]
    assert_equal "none", spawn[:env]["EVAL_TEMPERATURE"]
    assert_equal @dir.join("#{id}.json").to_s, spawn[:env]["EVAL_RESULTS"]
    assert_nil spawn[:env]["EVAL_NOTIFY"], "nobody to tell unless asked"
    assert spawn[:options][:pgroup]

    run = AssistantEval::RunFile.find(id)
    assert_predicate run, :running?, "the run shows up right away, before the task writes its file"
  end

  test "the profile to tell when the run ends travels in the environment" do
    launching { AssistantEval::Launcher.start!(notify: 42) }

    assert_equal "42", @spawned.sole[:env]["EVAL_NOTIFY"]
  end

  test "a draft file runs alone and is marked as a draft" do
    id = launching { AssistantEval::Launcher.start!(draft_file: "/tmp/drafts/abc123/10_skip_todays_dose.yml") }

    env = @spawned.sole[:env]
    assert_equal "/tmp/drafts/abc123/10_skip_todays_dose.yml", env["SCENARIO_FILE"]
    assert_nil env["SCENARIOS"]
    assert_equal "10_skip_todays_dose", AssistantEval::RunFile.find(id).data["draft"]
  end

  test "runs on OpenAI too" do
    launching { AssistantEval::Launcher.start!(provider: "openai", model: "gpt-5.6-luna") }

    assert_equal "openai", @spawned.sole[:env]["EVAL_PROVIDER"]
    assert_nil @spawned.sole[:env]["EVAL_TEMPERATURE"]
  end

  test "refuses unknown providers, odd model names, and a second run at once" do
    assert_raises(ArgumentError) { launching { AssistantEval::Launcher.start!(provider: "shell") } }
    assert_raises(ArgumentError) { launching { AssistantEval::Launcher.start!(model: "qwen3; rm -rf /") } }

    launching { AssistantEval::Launcher.start! }
    assert_raises(AssistantEval::Launcher::Busy) { launching { AssistantEval::Launcher.start! } }
    assert_equal 1, @spawned.size
  end

  def real_run(id = "20260929-100000-real")
    pid = Process.spawn("sleep", "30", pgroup: true)
    @dir.join("#{id}.json").write(JSON.generate(finished: false, pid: pid, results: []))
    [ AssistantEval::RunFile.find(id), pid ]
  end

  test "pause! stops the process group without killing it, resume! wakes it" do
    run, pid = real_run

    AssistantEval::Launcher.pause!(run)
    assert_eventually { run.status == :paused }

    AssistantEval::Launcher.resume!(run)
    assert_eventually { run.status == :running }
  ensure
    Process.kill("KILL", pid)
    Process.wait(pid)
  end

  test "pause! on a run that isn't going, and resume! on one that isn't paused, do nothing" do
    _, pid = real_run
    Process.kill("KILL", pid)
    Process.wait(pid)
    finished = AssistantEval::RunFile.find("20260929-100000-real")

    assert_nil AssistantEval::Launcher.pause!(finished)
    assert_nil AssistantEval::Launcher.resume!(finished)
  end

  test "cancel! wakes a paused run before terminating it — TERM alone would just sit pending" do
    run, pid = real_run
    AssistantEval::Launcher.pause!(run)
    assert_eventually { run.status == :paused }

    AssistantEval::Launcher.cancel!(run)
    Timeout.timeout(2) { Process.wait(pid) }
    assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
  end
end
