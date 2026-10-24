# frozen_string_literal: true

namespace :assistant do
  # The dashboard (AssistantEval::Launcher) drives it through the environment:
  # SCENARIOS, SCENARIO_FILE, SCENARIO_DIR, EVAL_RESULTS, EVAL_NOTIFY,
  # EVAL_SKIP_PREFLIGHT, EVAL_OUTAGE_* (AssistantEval::Run.from_env says each).
  desc "Run the assistant scenarios in eval/assistant/scenarios against the configured model: assistant:eval[RUNS,name_filter]"
  task :eval, [ :runs, :filter ] => :environment do |_, args|
    # Load all code now: a run measures the code as it was when it started,
    # even if files change while it runs (development loads lazily).
    Rails.application.eager_load!
    # Unbuffered, so the dashboard's log tail shows progress and a crash's last lines.
    # $stdout can be swapped by boot code; STDOUT is the real file descriptor.
    $stdout.sync = STDOUT.sync = true
    AssistantEval::Run.from_env(ENV, runs: args[:runs], filter: args[:filter]).call
  rescue AssistantEval::Run::NotStarted => e
    abort e.message
  end
end
