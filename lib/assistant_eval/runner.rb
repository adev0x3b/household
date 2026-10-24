# frozen_string_literal: true

require "active_support/testing/time_helpers"
require "timeout"

# Plays one scenario against the configured model, as a sandbox profile, in
# a transaction that is always rolled back, and checks the expectations.
#
# Each run ends passed, failed or error. An error is the plumbing, not the
# model: the harness crashed, the model server was unreachable, or the
# provider failed the request. Errors are never scored as failures.
module AssistantEval
  class Runner
    # ReplyJob outcomes that say nothing about the model's ability.
    INFRA_OUTCOMES = %w[unreachable rate_limited setup failed].freeze

    # A turn that runs past EVAL_TURN_TIMEOUT seconds (default 300): a
    # runaway thinking loop ends the scenario as an error, and the run moves on.
    class TurnTimeout < StandardError; end

    def self.turn_timeout = ENV.fetch("EVAL_TURN_TIMEOUT", 300).to_f

    # applied: change sets saved during the turn (a button press counts);
    # asked: a tool answered needs_input / waiting_for_user, so the turn
    # ended on a question or a card for the user. Expectations' turn checks read them.
    Turn = Data.define(:said, :tools, :reply, :seconds, :max_step_input, :outcome, :input_tokens, :output_tokens, :served, :applied, :asked)
    Turn.define_method(:initialize) do |max_step_input: 0, outcome: nil, input_tokens: 0, output_tokens: 0, served: [], applied: 0, asked: false, **rest|
      super(max_step_input:, outcome:, input_tokens:, output_tokens:, served:, applied:, asked:, **rest)
    end
    ASKED = %w[needs_input waiting_for_user].freeze
    Result = Data.define(:scenario, :passed, :failures, :turns, :seconds, :error, :error_class) do
      def initialize(error_class: nil, **rest) = super(error_class:, **rest)

      def status = error ? "error" : (passed ? "passed" : "failed")

      # The largest prompt any model step saw — compare with Assistant.context_tokens.
      def max_step_input = turns.map(&:max_step_input).max.to_i

      def to_h = super.merge(status: status)
    end

    # recorder: an AssistantEval::Recorder for the live tracker; index / rep:
    # this scenario run's place in the whole run.
    def initialize(scenario, recorder: nil, index: 0, rep: 1)
      @scenario = scenario
      @recorder = recorder
      @index = index
      @rep = rep
      @clock = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
    end

    def call
      started = monotonic
      @turns = []
      failures = []
      error = error_class = nil
      record("scenario_started", scenario: @scenario.name, rep: @rep, description: @scenario.description)
      begin
        @clock.travel_to(@scenario.today.in_time_zone.change(hour: 12))
        ActiveRecord::Base.transaction do
          profile = Sandbox.profile!
          Seeds.apply(@scenario.seed, profile)
          chat = Assistant::Chat.start!(profile: profile, locale: @scenario.locale, time_zone: "Europe/Rome")
          @recorder&.watch(chat_id: chat.id)
          @scenario.messages.each { |message| @turns << play(chat, message) }
          failures = Expectations.new(profile, turns: @turns).failures(@scenario.expect)
          raise ActiveRecord::Rollback
        end
        error_class, error = infra_error
      rescue TurnTimeout
        error_class = "timeout"
        error = "a turn took longer than #{self.class.turn_timeout.round}s (turn: #{@playing.to_s.truncate(60)})"
      rescue StandardError => e
        error_class = "harness"
        error = "#{e.class}: #{e.message.truncate(200)}"
      ensure
        @clock.travel_back
      end

      result = Result.new(scenario: @scenario.name, passed: error.nil? && failures.empty?, failures: error ? [] : failures,
                          turns: @turns, seconds: (monotonic - started).round(1), error: error, error_class: error_class)
      record("scenario_finished", scenario: @scenario.name, rep: @rep, status: result.status, failures: result.failures,
                                  error: error, error_class: error_class, seconds: result.seconds)
      result
    end

    # "!photo" and the text read from the photos (pages split on "---").
    PHOTO = /\A!photo\b\s*(?<text>.*)\z/m

    private

    def play(chat, message)
      started = monotonic
      if (dated = message.match(/\A@(\d{4}-\d{2}-\d{2})\s+(.*)\z/m))
        @clock.travel_to(Date.parse(dated[1]).in_time_zone.change(hour: 12))
        message = dated[2]
      end
      key = "#{@index}-#{@turns.size + 1}"
      @recorder&.turn = key
      photo = message.match(PHOTO)
      button = message.start_with?("!") && !photo
      record("turn_started", turn: key, said: message, date: Date.current.iso8601, button: button)
      applied_before = applied_ids(chat)
      if button
        pressed = Buttons.press(message.delete_prefix("!"), chat)
        return finish_turn(Turn.new(said: message, tools: [], reply: pressed, seconds: 0, applied: (applied_ids(chat) - applied_before).size), key, [])
      end

      chat.claim_reply! or raise "chat busy"
      if photo
        # What Assistant::LabReportOcrJob leaves after reading the photos: the
        # caption with their text appended (pages split on "---" lines).
        pages = photo[:text].split(/^---$/).map { |page| page.strip.presence }
        chat.ask_later(Assistant::LabReportOcrJob.attach_text(I18n.t("assistant.defaults.lab_photo_caption", locale: chat.locale), pages))
      else
        chat.ask_later(message)
      end
      ended = {}
      @playing = message
      on_turn = ->(*, payload) { ended = payload if payload[:chat_id] == chat.id }
      Timeout.timeout(self.class.turn_timeout, TurnTimeout) do
        ActiveSupport::Notifications.subscribed(on_turn, "turn.assistant") { Assistant::ReplyJob.perform_now(chat, chat.replying_since) }
      end
      turn = Assistant::Trace.new(chat.reload).turns.last
      finish_turn(Turn.new(said: message, tools: turn.steps.select { |s| s.kind == :tool }.map { |s| "#{s.name}#{"!" if s.result.is_a?(Hash) && s.result["ok"] == false}" },
                           reply: turn.steps.select { |s| s.kind == :reply }.map(&:text).last.to_s, seconds: (monotonic - started).round(1),
                           max_step_input: turn.max_step_input, outcome: ended[:outcome],
                           input_tokens: ended[:input_tokens].to_i, output_tokens: ended[:output_tokens].to_i,
                           served: Array(ended[:served]), applied: (applied_ids(chat) - applied_before).size,
                           asked: turn.steps.any? { |s| s.kind == :tool && s.result.is_a?(Hash) && ASKED.include?(s.result.dig("data", "status")) }),
                  key, turn.steps.select { |s| s.kind == :note }.map(&:text))
    end

    # Ids of the chat's applied change sets — time is frozen inside a
    # scenario, so "since the turn began" is counted by id, not by clock.
    def applied_ids(chat) = chat.change_sets.applied.pluck(:id)

    def finish_turn(turn, key, notes)
      record("turn_finished", turn: key, **turn.to_h.except(:said), notes: notes)
      turn
    end

    # [error_class, message] when a turn says nothing about the model: the
    # server was unreachable, the request failed, or another model answered.
    def infra_error
      if (broken = @turns.find { |turn| INFRA_OUTCOMES.include?(turn.outcome) })
        what = broken.outcome == "unreachable" ? "server was unreachable" : "request failed"
        return [ broken.outcome, "the model #{what} (turn: #{broken.said.truncate(60)})" ]
      end
      wrong = @turns.flat_map(&:served).uniq.reject { |served| same_model?(served, Assistant.model) }
      [ "wrong_model", "#{wrong.join(", ")} answered instead of #{Assistant.model}" ] if wrong.any?
    end

    # "qwen3-8b-household:latest" is qwen3-8b-household; an alias resolves to a dated snapshot.
    def same_model?(served, requested)
      served = served.to_s.delete_suffix(":latest")
      requested = requested.to_s.delete_suffix(":latest")
      served == requested || served.start_with?("#{requested}-")
    end

    def record(type, **data) = @recorder&.event(type, index: @index, **data)

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
