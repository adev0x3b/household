# frozen_string_literal: true

# Keeps what the model is sent within its context window. Every turn
# replays the whole chat, and each tool exchange adds its arguments
# and result verbatim, so a small local model's window fills up. Past the
# window a provider such as Ollama truncates silently, and the instructions
# go first.
#
# It works on the in-memory message list just before a reply; the database
# keeps every message. Oldest turns first, never the last KEEP_TURNS, it
# folds a turn's tool exchange into one line ("used record_groceries:
# saved") and then drops whole turns, leaving one note that lists what they
# said and did. It stops once the chat fits in TARGET_SHARE of the
# window after the overhead (the instructions, the tool schemas and the
# per-turn context); the rest is for this turn's own tool results and the
# reply. Nothing happens when the window isn't known.
#
#   Compaction.call(llm.messages, chat: chat)   # => Result, or nil when nothing was needed
module Assistant
  class Compaction
    TARGET_SHARE = 0.75
    KEEP_TURNS = 2
    CHARS_PER_TOKEN = 3.5
    # The prompt, the schemas and the context tokenize more loosely than chat
    # text, so their characters are counted at a wider ratio.
    OVERHEAD_CHARS_PER_TOKEN = 4.8
    MESSAGE_OVERHEAD = 4
    KEPT_TEXT = 240

    INSTRUCTIONS = Rails.root.join("app/prompts/assistant/bookkeeper_agent/instructions.txt.erb")

    Result = Data.define(:before, :after, :folded, :dropped, :overhead, :budget)

    # chat: whose instructions count in the overhead; overhead: tokens the
    # provider counts beyond the chat (tests pass 0).
    def self.call(messages, chat: nil, context_tokens: Assistant.context_tokens, overhead: nil)
      new(messages, chat:, context_tokens:, overhead:).call
    end

    # Tokens a message list would roughly cost: its text and tool arguments.
    def self.estimate(messages)
      messages.sum do |message|
        arguments = message.tool_calls.to_h.values.sum { |call| call.arguments.to_json.size }
        ((text(message).size + arguments) / CHARS_PER_TOKEN).ceil + MESSAGE_OVERHEAD
      end
    end

    # RubyLLM 2 keeps a message's content as a String; attachments go apart.
    def self.text(message) = message.content.to_s

    def initialize(messages, chat:, context_tokens:, overhead: nil)
      @chat = chat
      @messages = messages
      @limit = context_tokens
      @overhead = overhead
    end

    def call
      return unless @limit

      system, turns = split
      budget = (@limit * TARGET_SHARE).to_i - overhead
      before = self.class.estimate(turns.flatten)
      return if before <= budget

      folded = 0
      turns.each_with_index do |turn, i|
        break if i >= turns.size - KEEP_TURNS || self.class.estimate(turns.flatten) <= budget

        turns[i] = fold(turn)
        folded += 1
      end
      summary = []
      dropped = 0
      while turns.size > KEEP_TURNS && self.class.estimate(turns.flatten) + (summary.join.size / CHARS_PER_TOKEN) > budget
        summary.concat(lines_for(turns.shift))
        dropped += 1
      end
      return if folded.zero? && dropped.zero? # over budget with only the last turns left: nothing to take out

      note = summary.empty? ? [] : [ RubyLLM::Message.new(role: :user, content: Chat.note_text("Earlier in this conversation (left out to save room):\n#{summary.join("\n")}")) ]
      @messages.replace(note + turns.flatten + system)
      result = Result.new(before: before, after: self.class.estimate(note + turns.flatten), folded: folded, dropped: dropped,
                          overhead: overhead, budget: budget)
      ActiveSupport::Notifications.instrument("compaction.assistant", chat_id: @chat&.id, **result.to_h)
      result
    end

    # Tokens the provider counts beyond the chat. The previous
    # reply's usage row, set against the messages that step saw, says it
    # best; before any reply it is estimated from the tools' schemas, the
    # instructions and the per-turn context.
    def overhead
      @overhead ||= learned_overhead || self.class.fixed_overhead(@chat)
    end

    def self.fixed_overhead(chat)
      tools = chat ? BookkeeperAgent::TOOLS.sum { |tool| tool.description.to_s.size + tool.new(chat: chat).parameters_schema.to_json.size } : 0
      context = chat ? Context.new(chat).to_prompt.size : 0
      ((tools + INSTRUCTIONS.read.size + context) / OVERHEAD_CHARS_PER_TOKEN).ceil
    end

    private

    def learned_overhead
      return unless @chat

      last = @chat.assistant_messages.where(role: "assistant").order(:id).last
      return unless last

      actual = RubyLLM::ActiveRecord::Usage.where(message: last).order(:id).last&.input_tokens.to_i
      return unless actual.positive?

      dialogue = @messages.reject { |message| message.role == :system }
      index = dialogue.rindex { |message| message.role == :assistant && self.class.text(message) == last.content.to_s }
      [ actual - self.class.estimate(dialogue[0...index]), 0 ].max if index
    end

    # System messages (the instructions, appended last by RubyLLM; providers
    # put them first anyway) apart from the chat, which is cut into
    # turns: each starts at a message the user wrote, not an app note.
    def split
      system, rest = @messages.partition { |message| message.role == :system }
      turns = []
      rest.each do |message|
        turns << [] if turns.empty? || (message.role == :user && !self.class.text(message).start_with?(Chat::NOTE_PREFIX))
        turns.last << message
      end
      [ system, turns ]
    end

    # What the user said and the final reply (shortened), with the tool
    # exchange in between replaced by one line of what was used and how it went.
    def fold(turn)
      names = {}
      outcomes = {}
      kept = []
      reply = nil
      turn.each do |message|
        case message.role
        when :user then kept << message
        when :assistant
          if message.tool_call?
            message.tool_calls.each_value { |call| names[call.id] = call.name }
          elsif self.class.text(message).present?
            reply = message
          end
        when :tool then outcomes[message.tool_call_id] = outcome(self.class.text(message))
        end
      end
      kept << RubyLLM::Message.new(role: :assistant, content: used_line(names, outcomes)) if names.any?
      kept << RubyLLM::Message.new(role: :assistant, content: shorten(self.class.text(reply))) if reply
      kept
    end

    def used_line(names, outcomes) = "(used #{names.map { |id, name| "#{name}: #{outcomes.fetch(id, "ok")}" }.join(", ")})"

    # How a tool's result read: "saved", "needs_input", "failed".
    def outcome(text)
      data = JSON.parse(text)
      return "failed" if data.is_a?(Hash) && data["ok"] == false

      (data.is_a?(Hash) && data.dig("data", "status")) || "ok"
    rescue JSON::ParserError
      "ok"
    end

    # The turn's lines for the note. A turn is folded before it is dropped,
    # so its tool exchange is already one line.
    def lines_for(turn)
      turn.filter_map do |message|
        text = self.class.text(message)
        next if text.start_with?(Chat::NOTE_PREFIX)

        "- #{message.role}: #{shorten(text)}"
      end
    end

    def shorten(text) = ModelReply.new(text).answer.squish.truncate(KEPT_TEXT)
  end
end
