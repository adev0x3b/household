# frozen_string_literal: true

# Reads a run's events (written by AssistantEval::Recorder) for the live
# tracker: the state of every scenario run, what's happening now, and — for
# the page that polls — what changed since the last poll, as append/replace
# steps on stable DOM ids (a tool card is replaced when its call finishes,
# a reply bubble when more of the reply arrives).
module AssistantEval
  class RunEvents
    STATES = %w[queued running passed failed error].freeze
    # The events that say what the agent is doing (#now).
    ACTIVITY = %w[turn_started tool_started tool_call reply turn_finished scenario_finished].freeze

    def self.for(run) = new(RunFile.dir.join("#{run.id}.events.jsonl"))

    def initialize(path)
      @path = Pathname(path)
    end

    def exist? = @path.exist?

    # Every event, in order. A line cut off mid-write is skipped (the next
    # poll reads it whole), so positions count parsed events only.
    def all
      @all ||= exist? ? @path.each_line.filter_map { |line| parse(line) } : []
    end

    def size = all.size
    def last_at = all.last&.dig("t")

    # [{ "index", "scenario", "rep", "state" }] for every scenario run planned.
    def cases
      planned = all.find { |e| e["type"] == "run_started" }&.dig("cases") || []
      states = all.each_with_object({}) do |e, memo|
        memo[e["index"]] = "running" if e["type"] == "scenario_started"
        memo[e["index"]] = e["status"] if e["type"] == "scenario_finished"
      end
      planned.each_with_index.map { |c, i| c.merge("index" => i, "state" => states.fetch(i, "queued")) }
    end

    # What the agent is doing now: nil between scenarios, else
    # { "phase" => "model" | "tool", "tool" => name } since the last event.
    def now
      last = all.reverse_each.find { |e| ACTIVITY.include?(e["type"]) }
      case last&.dig("type")
      when "tool_started" then { "phase" => "tool", "tool" => last["tool"] }
      when "turn_started", "tool_call", "reply" then last["button"] ? nil : { "phase" => "model" }
      end
    end

    # The whole timeline as it should look now: one card per tool call (its
    # finished state if it finished), one reply bubble per turn (the final
    # text once the turn ended).
    def display
      finished_tools = all.select { |e| e["type"] == "tool_call" }.to_h { |e| [ e["seq"], e ] }
      final_replies = all.select { |e| e["type"] == "turn_finished" }.to_h { |e| [ e["turn"], e["reply"] ] }
      shown_replies = {}
      all.each_with_object([]) do |e, items|
        case e["type"]
        when "run_started", "tool_call" then next
        when "tool_started" then items << (finished_tools[e["seq"]] || e)
        when "reply"
          next if shown_replies[e["turn"]]

          shown_replies[e["turn"]] = true
          items << e.merge("text" => final_replies[e["turn"]].presence || last_reply(e["turn"]))
        when "turn_finished"
          items << e.merge("type" => "reply", "text" => e["reply"]) if e["reply"].present? && !shown_replies[e["turn"]]
          items << e
        else items << e
        end
      end
    end

    # Changes since event number `after`: [[:append | :replace, target_id, event]].
    # Targets: "eval-timeline" (append), "eval-case-<index>", "eval-tool-<seq>",
    # "eval-reply-<turn>".
    def updates(after)
      all.each_with_index.drop(after).flat_map do |e, i|
        earlier = all.first(i)
        case e["type"]
        when "run_started" then [ [ :replace, "eval-cases", nil ] ]
        when "scenario_started", "scenario_finished" then [ [ :append, "eval-timeline", e ], [ :replace, "eval-case-#{e["index"]}", nil ] ]
        when "tool_call"
          started = earlier.any? { |x| x["type"] == "tool_started" && x["seq"] == e["seq"] }
          [ started ? [ :replace, "eval-tool-#{e["seq"]}", e ] : [ :append, "eval-timeline", e ] ]
        when "reply"
          shown = earlier.any? { |x| x["type"] == "reply" && x["turn"] == e["turn"] }
          [ shown ? [ :replace, "eval-reply-#{e["turn"]}", e ] : [ :append, "eval-timeline", e ] ]
        when "turn_finished"
          shown = earlier.any? { |x| x["type"] == "reply" && x["turn"] == e["turn"] }
          reply = e.merge("type" => "reply", "text" => e["reply"])
          steps = e["reply"].present? ? [ shown ? [ :replace, "eval-reply-#{e["turn"]}", reply ] : [ :append, "eval-timeline", reply ] ] : []
          steps + [ [ :append, "eval-timeline", e ] ]
        else [ [ :append, "eval-timeline", e ] ]
        end
      end
    end

    private

    def last_reply(turn) = all.reverse_each.find { |x| x["type"] == "reply" && x["turn"] == turn }&.dig("text")

    def parse(line)
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end
  end
end
