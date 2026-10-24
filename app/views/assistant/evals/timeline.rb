# frozen_string_literal: true

# The live tracker's timeline, one entry per kind of event the recorder
# writes (AssistantEval::Recorder, AssistantEval::Run), each a Timeline::Entry
# found by the event's type: a scenario header, what the user said, a tool
# call (running, then its result), the reply, the turn's numbers, the
# scenario's result, the run's end, and an outage of the model server.
module Views::Assistant::Evals::Timeline
  BY_TYPE = {
    "scenario_started" => Views::Assistant::Evals::Timeline::ScenarioStarted,
    "turn_started" => Views::Assistant::Evals::Timeline::TurnStarted,
    "tool_started" => Views::Assistant::Evals::Timeline::ToolCall,
    "tool_call" => Views::Assistant::Evals::Timeline::ToolCall,
    "reply" => Views::Assistant::Evals::Timeline::Reply,
    "turn_finished" => Views::Assistant::Evals::Timeline::TurnFinished,
    "scenario_finished" => Views::Assistant::Evals::Timeline::ScenarioFinished,
    "run_finished" => Views::Assistant::Evals::Timeline::RunFinished,
    "outage_started" => Views::Assistant::Evals::Timeline::Outage,
    "outage_ended" => Views::Assistant::Evals::Timeline::Outage
  }.freeze

  def self.for(event) = BY_TYPE.fetch(event["type"]).new(event: event)
end
