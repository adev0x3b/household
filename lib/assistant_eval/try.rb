# frozen_string_literal: true

require "active_support/testing/time_helpers"

module AssistantEval
  # Turns played against the configured model and then rolled back, as
  # `bin/rails assistant:try` plays them: what the model does with a few
  # messages, read in a terminal — each turn's tool calls with their
  # arguments and results, notes to the model, the reply, the tokens
  # (Assistant::Trace).
  #
  #   AssistantEval::Try.new(turns: AssistantEval::Try.turns_from("I took my dose|@2026-09-25 and today's")).call
  #
  # A turn starting "@YYYY-MM-DD " is played on that day; `today:` is the
  # first day. `profile:` names whose data it plays with (a username), else
  # the first profile, or a throwaway one with `fresh: true` (Sandbox).
  class Try
    Busy = Class.new(StandardError)

    # "first|second|@2026-09-25 third" → the turns ("\n" in the text is a newline).
    def self.turns_from(text) = text.to_s.split("|").map { |turn| turn.gsub("\\n", "\n").strip }.reject(&:empty?)

    def initialize(turns:, profile: nil, fresh: false, locale: "en", today: nil, out: $stdout)
      @turns = turns
      @username = profile
      @fresh = fresh
      @locale = locale
      @today = today
      @out = out
      @clock = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
    end

    def call
      @clock.travel_to Time.zone.parse("#{@today} 12:00") if @today
      ActiveRecord::Base.transaction do
        chat = Assistant::Chat.start!(profile: profile, locale: @locale, time_zone: Time.zone.name)
        @out.puts "Trying as #{chat.profile.username} with #{chat.model_id} (#{chat.provider}); everything is rolled back afterwards."
        @turns.each { |text| play(chat, text) }
        raise ActiveRecord::Rollback
      end
    ensure
      @clock.travel_back
    end

    private

    def profile
      if @fresh then Sandbox.profile!
      elsif @username then Profile.find_by!(username: @username)
      else Profile.order(:id).first
      end
    end

    def play(chat, text)
      if (dated = text.match(/\A@(\d{4}-\d{2}-\d{2})\s+(.*)\z/m))
        @clock.travel_to Time.zone.parse("#{dated[1]} 12:00")
        text = dated[2]
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      chat.claim_reply! or raise Busy, "chat is busy"
      chat.ask_later(text)
      Assistant::ReplyJob.perform_now(chat, chat.replying_since)

      print_turn(Assistant::Trace.new(chat.reload).turns.last, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    def print_turn(turn, seconds)
      @out.puts "", "── #{Date.current} · #{seconds.round(1)}s · #{turn.tool_calls} tool calls · " \
                    "#{turn.input_tokens} in / #{turn.output_tokens} out tokens"
      @out.puts "USER: #{turn.user}"
      turn.steps.each do |step|
        case step.kind
        when :tool
          @out.puts "  → #{step.name} #{Assistant::Trace.brief(step.arguments, limit: 1000)}"
          @out.puts "    ← #{Assistant::Trace.brief(step.result, limit: 1000)}"
        when :note then @out.puts "  (note) #{step.text}"
        when :reply then @out.puts "ASSISTANT: #{step.text}"
        end
      end
    end
  end
end
