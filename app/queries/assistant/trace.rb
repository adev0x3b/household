# frozen_string_literal: true

# What happened in a chat, turn by turn, for debugging: each user message,
# then every tool call the model made with its arguments and the result it
# got back, the notes, and the reply. It is read from what RubyLLM stores,
# for the chat's debug panel and `bin/rails assistant:trace[CHAT_ID]`.
module Assistant
  class Trace
    Step = Data.define(:kind, :name, :arguments, :result, :text) # kind: :tool, :reply, :note
    # Marks a reply the job dropped and retried (kept hidden, Assistant::ReplyJob).
    RETRIED = "(retried)"
    Turn = Data.define(:number, :user, :at, :steps, :input_tokens, :output_tokens, :max_step_input) do
      def tool_calls = steps.count { |s| s.kind == :tool }
    end

    def self.brief(value, limit: 300) = value.to_json.truncate(limit)

    def initialize(chat)
      @chat = chat
    end

    def turns
      @turns ||= begin
        grouped = []
        messages.each do |message|
          if (message.role == "user" && !message.hidden) || grouped.empty?
            grouped << { user: (message.content if message.role == "user" && !message.hidden), at: message.created_at, steps: [], input: 0, output: 0, max_step: 0 }
            next if message.role == "user" && !message.hidden
          end
          add(grouped.last, message)
        end
        grouped.each_with_index.map do |t, i|
          Turn.new(number: i + 1, user: t[:user], at: t[:at], steps: t[:steps], input_tokens: t[:input], output_tokens: t[:output], max_step_input: t[:max_step])
        end
      end
    end

    # Plain-text rendering for the terminal.
    def to_text
      lines = [ "Chat ##{@chat.id} · #{@chat.profile.username} · #{@chat.model_id} (#{@chat.provider}) · #{@chat.locale}" ]
      turns.each do |turn|
        lines << "" << "── Turn #{turn.number} · #{turn.at&.strftime("%F %T")} · #{turn.tool_calls} tool calls · #{turn.input_tokens} in / #{turn.output_tokens} out tokens · largest step #{turn.max_step_input}#{" of #{Assistant.context_tokens}" if Assistant.context_tokens}#{" ⚠ near the context limit" if Assistant.near_context_limit?(turn.max_step_input)}"
        lines << "USER: #{turn.user}" if turn.user
        turn.steps.each do |step|
          case step.kind
          when :tool
            lines << "  → #{step.name} #{self.class.brief(step.arguments, limit: 1000)}"
            lines << "    ← #{self.class.brief(step.result, limit: 1000)}"
          when :note then lines << "  (note) #{step.text}"
          when :reply then lines << "ASSISTANT: #{step.text}"
          end
        end
      end
      lines.join("\n")
    end

    private

    def messages
      @chat.assistant_messages.includes(:ruby_llm_usages, ruby_llm_tool_calls: :result).order(:id)
    end

    def add(turn, message)
      message.ruby_llm_usages.each do |usage|
        turn[:input] += usage.input_tokens.to_i
        turn[:max_step] = [ turn[:max_step], usage.input_tokens.to_i ].max
        turn[:output] += usage.output_tokens.to_i
      end

      case message.role
      when "assistant"
        message.ruby_llm_tool_calls.each do |call|
          turn[:steps] << Step.new(kind: :tool, name: call.name, arguments: call.arguments, result: parse(call.result&.content), text: nil)
        end
        text = ModelReply.new(message.content).answer
        text = "#{RETRIED} #{text}" if message.hidden && text.present?
        turn[:steps] << Step.new(kind: :reply, name: nil, arguments: nil, result: nil, text: text) if text.present?
      when "system", "user" # a hidden user message is the app's note to the model (Assistant::Chat#note_for_model!)
        turn[:steps] << Step.new(kind: :note, name: nil, arguments: nil, result: nil, text: message.content.to_s.delete_prefix(Assistant::Chat::NOTE_PREFIX))
      end
    end

    def parse(content)
      return if content.nil?

      JSON.parse(content)
    rescue JSON::ParserError
      content
    end
  end
end
