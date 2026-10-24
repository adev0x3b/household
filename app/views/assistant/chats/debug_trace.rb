# frozen_string_literal: true

# A chat as the model saw it, for admins and development (?debug=1,
# Assistant::ChatPolicy#debug?): tool calls with their raw arguments and
# results, tokens, and each turn's context. The one page that shows raw JSON.
#
# The controller hands it what it shows: the trace (Assistant::Trace), the
# chat's change sets in order, the context's prompt (Assistant::Context),
# and whether the viewer runs the app, who can keep the chat as an eval.
class Views::Assistant::Chats::DebugTrace < Views::Base
  RESULT_LIMIT = 4000

  def initialize(chat:, trace:, change_sets:, prompt:, admin:)
    @chat = chat
    @trace = trace
    @change_sets = change_sets
    @prompt = prompt
    @admin = admin
  end

  def view_template
    section(class: "assistant-debug", aria: { label: t("assistant.debug.title") }) do
      p(class: "assistant-debug__meta") { "#{@chat.model_id} · #{@chat.provider} · #{@chat.locale} · #{@chat.time_zone}" }
      if @admin && @trace.turns.any?(&:user)
        a(href: new_assistant_evals_scenario_path(from_chat: @chat.id), class: "assistant-debug__action") do
          render Components::Icon.new("fa-vial")
          plain " #{t("assistant.evals.save_chat")}"
        end
      end
      @trace.turns.each { |turn| render_turn(turn) }
      if @change_sets.any?
        details(class: "assistant-debug__turn") do
          summary { t("assistant.debug.change_sets") }
          @change_sets.each do |set|
            pre(class: "assistant-debug__code") do
              JSON.pretty_generate(set.slice(:id, :status, :intents, :operations, :display, :undo_log, :undoable, :acknowledged_warnings))
            end
          end
        end
      end
      details(class: "assistant-debug__turn") do
        summary { t("assistant.debug.context") }
        pre(class: "assistant-debug__code") { @prompt }
      end
    end
  end

  private

  def render_turn(turn)
    details(class: "assistant-debug__turn", open: turn == @trace.turns.last) do
      summary do
        plain t("assistant.debug.turn", number: turn.number, tools: turn.tool_calls,
                                        input: turn.input_tokens, output: turn.output_tokens)
        span(class: "assistant-debug__user") { turn.user.to_s.truncate(60) }
        render_context_use(turn)
      end
      turn.steps.each { |step| render_step(step) }
    end
  end

  def render_context_use(turn)
    near = ::Assistant.near_context_limit?(turn.max_step_input)
    span(class: "assistant-debug__context#{" assistant-debug__context--near" if near}") do
      if ::Assistant.context_tokens
        t("assistant.debug.largest_step_of", tokens: turn.max_step_input, limit: ::Assistant.context_tokens)
      else
        t("assistant.debug.largest_step", tokens: turn.max_step_input)
      end
    end
  end

  def render_step(step)
    case step.kind
    when :tool
      div(class: "assistant-debug__step#{" assistant-debug__step--failed" if step.result.is_a?(Hash) && step.result["ok"] == false}") do
        p(class: "assistant-debug__tool") { step.name }
        p(class: "assistant-debug__label") { t("assistant.debug.arguments") }
        pre(class: "assistant-debug__code") { JSON.pretty_generate(step.arguments || {}) }
        p(class: "assistant-debug__label") { t("assistant.debug.result") }
        pre(class: "assistant-debug__code") { pretty(step.result) }
      end
    when :note
      p(class: "assistant-debug__note") { "#{t("assistant.debug.note")}: #{step.text}" }
    when :reply
      p(class: "assistant-debug__label") { t("assistant.debug.reply") }
      pre(class: "assistant-debug__code") { step.text }
    end
  end

  def pretty(value)
    text = value.is_a?(String) ? value : JSON.pretty_generate(value)
    text.truncate(RESULT_LIMIT)
  end
end
