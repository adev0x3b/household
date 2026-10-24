# frozen_string_literal: true

# Starts `assistant:eval` from the eval dashboard, in its own process: the
# runner travels in time (travel_to stubs the clock process-wide), so it
# must never run inside the web server. One run at a time — the model
# server has one GPU.
#
#   run_id = Launcher.start!(scenarios: ["04_lab_report_alone"], runs: 3, provider: "ollama", model: "qwen3-8b-household")
module AssistantEval
  module Launcher
    class Busy < StandardError; end

    PROVIDERS = Assistant::Setting::PROVIDERS
    MODEL_FORMAT = Assistant::Setting::MODEL_FORMAT
    MAX_RUNS = 10

    module_function

    # Returns the new run's id (its RunFile). `draft_file`: one unsaved
    # scenario written by ScenarioDraft#write_temp!; `scenario_dir`: every
    # scenario in a directory (Lexicon::AgentEval's generated ones); `env`:
    # more for the eval process (LEXICON_IMPORTS); `notify`: the profile to
    # tell when the run ends (EVAL_NOTIFY). Raises Busy, ArgumentError,
    # or Preflight::Unavailable when the model isn't there (or its server).
    def start!(scenarios: [], runs: 1, provider: nil, model: nil, draft_file: nil, scenario_dir: nil, env: {}, notify: nil)
      provider = provider.presence || Assistant.provider.to_s
      model = model.presence || Assistant.model
      raise Busy, "an eval is already running" if RunFile.running
      raise ArgumentError, "unknown provider #{provider.inspect}" unless PROVIDERS.include?(provider.to_s)
      raise ArgumentError, "invalid model #{model.inspect}" unless model.to_s.match?(MODEL_FORMAT)

      Preflight.check!(provider: provider, model: model)
      runs = runs.to_i.clamp(1, MAX_RUNS)
      id = "#{Time.now.utc.strftime("%Y%m%d-%H%M%S")}-#{model.tr(":/", "__")}"
      FileUtils.mkdir_p(RunFile.dir)
      # EVAL_*: the run's own provider and model, over the saved settings (Assistant).
      env = { "EVAL_PROVIDER" => provider.to_s, "EVAL_MODEL" => model.to_s,
              "EVAL_RESULTS" => RunFile.dir.join("#{id}.json").to_s,
              "SCENARIOS" => draft_file || scenario_dir ? nil : Array(scenarios).join(","),
              "SCENARIO_FILE" => draft_file&.to_s, "SCENARIO_DIR" => scenario_dir&.to_s,
              "EVAL_NOTIFY" => notify&.to_s }.merge(env.to_h.transform_keys(&:to_s))
      env["EVAL_TEMPERATURE"] = "none" if provider.to_s == "anthropic" # newer Claude models reject it
      pid = Process.spawn(env, Rails.root.join("bin/rails").to_s, "assistant:eval[#{runs}]",
                          chdir: Rails.root.to_s, out: RunFile.dir.join("#{id}.log").to_s, err: %i[child out], pgroup: true)
      Process.detach(pid)
      # The task needs a few seconds to boot before it writes this file;
      # write it now so the run shows (and counts as running) immediately.
      File.write(RunFile.dir.join("#{id}.json"), JSON.generate(
                                                   model: model, provider: provider, runs: runs, pid: pid, started_at: Time.current.iso8601, finished: false,
                                                   draft: draft_file && File.basename(draft_file.to_s, ".yml"), results: []
                                                 ))
      FileUtils.touch(RunFile.dir.join("#{id}.events.jsonl")) # the live tracker shows from the first second
      id
    end

    # Stops a run and everything it started (its process group). A stopped
    # process only ever wakes for SIGCONT/SIGKILL — TERM alone would just
    # sit pending until someone resumed it — so a paused run is woken first.
    def cancel!(run)
      paused = run.status == :paused
      return unless run.running? || paused

      pgid = -Process.getpgid(run.pid)
      Process.kill("CONT", pgid) if paused
      Process.kill("TERM", pgid)
    rescue Errno::ESRCH
      nil
    end

    # Freezes the run's process group (and so the model it's calling) without
    # losing anything: whatever's mid-flight just waits, and resume! picks up
    # exactly where it left off. Frees the GPU for something else meanwhile —
    # Ollama's own idle timeout unloads the model once nothing's asking for it.
    def pause!(run)
      return unless run.running?

      Process.kill("STOP", -Process.getpgid(run.pid))
      settle { run.status == :paused }
    rescue Errno::ESRCH
      nil
    end

    def resume!(run)
      return unless run.status == :paused

      Process.kill("CONT", -Process.getpgid(run.pid))
      settle { run.status != :paused }
    rescue Errno::ESRCH
      nil
    end

    # A signal lands a moment after kill returns, and the page that follows
    # reads the process's state from /proc (RunFile#paused?): wait for it,
    # a second at most, so the page says what was just done.
    def settle(seconds = 1.0)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      sleep 0.01 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end

    # Models to offer: the configured one, plus what its provider has (it
    # may be offline — then just the configured one).
    def models
      ([ Assistant.model ] + Assistant::Connection.models(Assistant.provider)).uniq
    end
  end
end
