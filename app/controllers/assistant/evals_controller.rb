# frozen_string_literal: true

# GET /assistant/evals — the evals' overview: how the latest run did, the
# pass rate over time, the scenarios that fail most, each model. Run (the
# run modal, every scenario) is the navbar's; it waits while another run goes.
class Assistant::EvalsController < Assistant::Evals::BaseController
  RECENT_RUNS = 30

  def index
    running = AssistantEval::RunFile.running
    overview = AssistantEval::Overview.new(runs: AssistantEval::RunFile.recent(RECENT_RUNS).reject(&:draft?), scenarios: AssistantEval::Scenario.all)
    render_page Views::Assistant::Evals::Overview.new(overview: overview, running: running)
  end
end
