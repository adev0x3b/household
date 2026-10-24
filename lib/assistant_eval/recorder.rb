# frozen_string_literal: true

# Writes what the agent does during an eval run, as it happens, one JSON
# line per event in tmp/assistant_evals/<id>.events.jsonl — the dashboard's
# live tracker reads it (AssistantEval::RunEvents).
#
# Tool calls and reply text come from the app's own notifications
# (tool_call.assistant in Assistant::Tool#call, reply_text.assistant in
# Assistant::Broadcaster), filtered to the chat being evaluated; the
# runner reports scenarios and turns. Times are wall-clock (CLOCK_REALTIME):
# inside a scenario `travel_to` freezes Time.now.
module AssistantEval
  class Recorder
    REPLY_EVERY = 1.0 # seconds between reply snapshots
    BRIEF = 3000      # characters of a tool result kept

    attr_reader :path

    def initialize(path)
      @path = Pathname(path)
      @file = File.open(@path, "a")
      @file.sync = true
      @tool_seq = 0
      @tools = {}
      @chat_id = nil
      @turn = nil
      @subscriptions = [
        ActiveSupport::Notifications.subscribe("tool_call.assistant", ToolSubscriber.new(self)),
        ActiveSupport::Notifications.subscribe("reply_text.assistant") { |*, payload| reply(payload) }
      ]
    end

    # The runner says which chat and turn is being played.
    def watch(chat_id:) = @chat_id = chat_id

    def turn=(key)
      @turn = key
      @last_reply = nil
    end

    def event(type, **data)
      @file.puts(JSON.generate({ type: type, t: now, **data }))
    end

    def close
      @subscriptions.each { |subscription| ActiveSupport::Notifications.unsubscribe(subscription) }
      @file.close
    end

    # Start and finish of each tool call, so the tracker shows it running.
    class ToolSubscriber
      def initialize(recorder) = @recorder = recorder
      def start(_name, id, payload) = @recorder.tool_started(id, payload)
      def finish(_name, id, payload) = @recorder.tool_finished(id, payload)
    end

    def tool_started(id, payload)
      return unless payload[:chat_id] == @chat_id

      seq = @tools[id] = (@tool_seq += 1)
      @tool_started_at = now
      event("tool_started", seq: seq, turn: @turn, tool: payload[:tool], arguments: payload[:arguments])
    end

    def tool_finished(id, payload)
      seq = @tools.delete(id)
      return if seq.nil?

      event("tool_call", seq: seq, turn: @turn, tool: payload[:tool], arguments: payload[:arguments], ok: payload[:ok],
                         error: payload[:error], result: brief(payload[:result]), ms: ((now - @tool_started_at) * 1000).round)
    end

    private

    def reply(payload)
      return unless payload[:chat_id] == @chat_id && payload[:text].present?
      return if @last_reply && now - @last_reply < REPLY_EVERY

      @last_reply = now
      event("reply", turn: @turn, text: payload[:text])
    end

    def brief(value) = value.to_json.then { |json| json.length > BRIEF ? "#{json[0, BRIEF]}…" : json }

    def now = Process.clock_gettime(Process::CLOCK_REALTIME).round(3)
  end
end
