# frozen_string_literal: true

# One assistant turn: the model reads the chat, calls tools (RubyLLM's
# acts_as_chat saves each call as it happens) and streams its reply.
#
# The job is never retried, because a retry would repeat what the tools did.
# RubyLLM already retries a failed request (config.max_retries).
#
# It answers the message that claimed the chat at claimed_at, and nothing
# later: a reply that comes after Assistant::ReplyTimeoutJob gave up on it
# isn't wanted any more, and must not free a chat claimed again since.
class Assistant::ReplyJob < ApplicationJob
  queue_as :assistant
  runs_once

  MAX_TOOL_CALLS = 12
  STREAM_EVERY = 0.2 # seconds between streamed reply updates

  def perform(chat, claimed_at)
    return unless chat.replying_since == claimed_at

    @chat = chat
    @claimed_at = claimed_at
    started = Time.current
    @outcome = "ok"
    I18n.with_locale(@chat.locale) do
      Time.use_zone(@chat.time_zone_or_default) { reply }
    end
  ensure
    finish_turn(started) if @chat
  end

  private

  def reply
    @agent_chat = Assistant::BookkeeperAgent.for(@chat)
    @llm = @agent_chat.to_llm
    compact
    @calls = Calls.new(@llm)
    answer = complete
    note = retry_note(answer)
    answer = try_again(answer, note) if note
    deliver(answer)
  rescue RubyLLM::CancelledError
    fail_with(@calls&.too_many? ? "too_many_steps" : "cancelled")
  rescue StandardError => e
    trouble = Trouble.of(e)
    Rails.error.report(trouble.reported(e), handled: true, severity: trouble.severity, context: { chat_id: @chat.id, step: "reply" })
    fail_with(trouble.reason.to_s)
  end

  # The history is trimmed to the model's window before anything is sent
  # (Assistant::Compaction); what is stored stays whole.
  def compact
    compacted = Assistant::Compaction.call(@llm.messages, chat: @chat)
    return unless compacted

    Rails.logger.info("[assistant] chat=#{@chat.id} compacted the history: ~#{compacted.before} → ~#{compacted.after} tokens " \
                      "(#{compacted.folded} turns folded, #{compacted.dropped} dropped)")
  end

  # Streams one completion as it comes and returns the answer it ended on.
  def complete
    text = +""
    last_push = 0.0
    @agent_chat.complete do |chunk|
      next if chunk.content.blank?

      text << chunk.content
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      next if now - last_push < STREAM_EVERY

      last_push = now
      Assistant::Broadcaster.reply_text(@chat, text)
    end
    @agent_chat.assistant_messages.where(role: "assistant").order(:id).last
  end

  # Small models sometimes write the tool calls they mean to make instead of
  # making them, answer the user after a failed call instead of fixing it,
  # or think until the output cap and say nothing. Each gets a note telling
  # the model what went wrong, and one more try.
  def retry_note(answer)
    return unless answer

    if ran_out?(answer) then Assistant::Notes.render(:ran_out)
    elsif pseudo_tool_calls?(answer.content) then Assistant::Notes.render(:pseudo_call)
    elsif @calls.failed_unexplained? then Assistant::Notes.render(:failed_call, error: @calls.errors.uniq.join("; "))
    end
  end

  # The answer is hidden (kept for the trace, out of what the model reads
  # next) and the note goes in as a user-role message, never system (see
  # Assistant::Chat#note_for_model!), so the model has it on its next try.
  def try_again(answer, note)
    Rails.logger.info("[assistant] chat=#{@chat.id} retrying")
    Rails.logger.debug do
      "[assistant] chat=#{@chat.id} retrying (#{note.truncate(60)}): #{answer.content.to_s.squish.truncate(300)}"
    end
    @llm.messages.pop if @llm.messages.last&.role == :assistant && @llm.messages.last.content.to_s == answer.content.to_s
    answer.update!(hidden: true)
    @calls.forget_errors
    @agent_chat.add_message(role: :user, content: Assistant::Chat.note_text(note))
    @chat.hide_last!(:user)
    Assistant::Broadcaster.reply_text(@chat, nil)
    complete
  end

  def deliver(answer)
    if answer&.content.present?
      Assistant::Broadcaster.finish(@chat, answer)
    else
      fail_with("no_answer")
    end
  end

  def fail_with(outcome)
    @outcome = outcome
    Assistant::Broadcaster.failure(@chat, @chat.reply_failures.create!(reason: outcome))
  end

  # A step that ended with nothing, no text and no tool call: the model
  # spent the whole max_output_tokens thinking.
  def ran_out?(answer) = answer.content.to_s.strip.empty? && answer.ruby_llm_tool_calls.none?

  def pseudo_tool_calls?(content)
    names = Assistant::BookkeeperAgent::TOOLS.map(&:tool_name).join("|")
    content.to_s.match?(/\b(?:#{names})\s*\(|"name"\s*:\s*"(?:#{names})"/)
  end

  # How the turn ended goes to the log and to whoever subscribes to
  # "turn.assistant" (the eval runner does). An instrument nobody listens
  # to costs nothing.
  def finish_turn(started)
    @chat.release_reply!(@claimed_at)
    stats = log_turn(started)
    ActiveSupport::Notifications.instrument("turn.assistant", chat_id: @chat.id, outcome: @outcome, model: @chat.model_id,
                                                              served: @calls ? @calls.served.to_a : [], **stats)
  end

  # One summary line per turn, next to the per-tool lines:
  #   [assistant] chat=7 turn done in 21.4s qwen3:8b tools=3 tokens=2394/1217 outcome=ok
  # Returns the turn's numbers ({} when they can't be read).
  def log_turn(started)
    usages = RubyLLM::ActiveRecord::Usage.where(chat: @chat, created_at: started..)
    stats = { tools: RubyLLM::ActiveRecord::ToolCall.where(message: @chat.assistant_messages.where(created_at: started..)).count,
              input_tokens: usages.sum(:input_tokens), output_tokens: usages.sum(:output_tokens),
              max_step_input: usages.maximum(:input_tokens).to_i }
    Rails.logger.info(
      "[assistant] chat=#{@chat.id} turn done in #{(Time.current - started).round(1)}s #{@chat.model_id} tools=#{stats[:tools]} " \
      "tokens=#{stats[:input_tokens]}/#{stats[:output_tokens]} outcome=#{@outcome}"
    )
    if Assistant.near_context_limit?(stats[:max_step_input])
      Rails.logger.warn("[assistant] chat=#{@chat.id} a step used #{stats[:max_step_input]} of #{Assistant.context_tokens} context tokens, so the prompt may have been truncated")
    end
    stats
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { chat_id: @chat.id, step: "turn log" })
    {}
  end
end
