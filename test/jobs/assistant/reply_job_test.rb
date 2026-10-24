# frozen_string_literal: true

require "test_helper"

class Assistant::ReplyJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  # Stands in for the configured chat record: streams two chunks, then
  # stores the answer the way RubyLLM's acts_as_chat would.
  class FakeChat < SimpleDelegator
    # `tool_results`: per completion, the tool results it "produced".
    def initialize(chat, error: nil, answer: "Saved your appointment.", answers: nil, tool_results: [])
      super(chat)
      @error = error
      @answers = answers || [ answer ]
      @tool_results = tool_results
    end

    FakeLLM = Struct.new(:messages, :result_callbacks) do
      def before_tool_call(&) = self
      def after_tool_result(&block) = result_callbacks << block
      def after_message(&) = self
      def cancel; end
    end

    def to_llm = @llm ||= FakeLLM.new([], [])

    def complete
      raise @error if @error

      Array(@tool_results.shift).each { |result| to_llm.result_callbacks.each { |callback| callback.call(result) } }
      yield RubyLLM::Chunk.new(role: :assistant, content: "Saved ")
      yield RubyLLM::Chunk.new(role: :assistant, content: "your appointment.")
      assistant_messages.create!(role: "assistant", content: @answers.shift)
    end

    def add_message(role:, content:) = assistant_messages.create!(role: role.to_s, content: content)
  end

  setup do
    @chat = assistant_chat(profiles(:alice))
    @chat.claim_reply!
  end

  # What the chat was sent, as words (the streams' templates read as text).
  def streamed(&) = capture_turbo_stream_broadcasts(@chat, &).map(&:text).join(" ")

  # The app's one note to the model this turn: a hidden user message, never system.
  def note = -> { @chat.assistant_messages.where(role: "user", hidden: true).sole.content.delete_prefix(Assistant::Chat::NOTE_PREFIX) }

  def perform_with(fake)
    swapping(Assistant::BookkeeperAgent, :for, ->(_chat) { fake }) do
      Assistant::ReplyJob.perform_now(@chat, @chat.replying_since)
    end
  end

  test "a reply is stored, streamed, and frees the chat" do
    streams = streamed { perform_with(FakeChat.new(@chat)) }

    assert_equal "Saved your appointment.", @chat.assistant_messages.where(role: "assistant").last.content
    assert_not @chat.reload.replying?
    assert_includes streams, "Saved your appointment."
  end

  test "an unreachable model shows a notice, frees the chat, and is reported as a warning" do
    streams = nil
    report = assert_error_reported(Assistant::ReplyJob::Trouble::ModelUnreachable) do
      streams = streamed { perform_with(FakeChat.new(@chat, error: Faraday::ConnectionFailed.new("down"))) }
    end

    assert_not @chat.reload.replying?
    assert_includes streams, I18n.t("assistant.errors.unreachable")
    assert_equal :warning, report.severity
    assert_kind_of Faraday::ConnectionFailed, report.error.cause, "the provider's own error stays with the report"
    assert_equal "unreachable", @chat.reply_failures.sole.reason, "kept, so the thread still says why after a reload"
  end

  # A provider's answer as RubyLLM wraps it.
  Answer = Struct.new(:status, :body)

  # What the person reads for each trouble, and what whoever runs the app is told.
  {
    RubyLLM::ServiceUnavailableError.new("Service Unavailable", response: Answer.new(503, "")) => [ :unreachable, :warning, "ModelUnreachable" ],
    RubyLLM::OverloadedError.new => [ :unreachable, :warning, "ModelUnreachable" ],
    RubyLLM::RateLimitError.new("Rate limit reached for requests: limit 50, used 50") => [ :rate_limited, :warning, "ModelRateLimited" ],
    RubyLLM::UnauthorizedError.new("invalid x-api-key") => [ :setup, :error, "ModelKeyRefused" ],
    RubyLLM::ConfigurationError.new("anthropic_api_key is missing") => [ :setup, :error, "ModelKeyRefused" ],
    RubyLLM::PaymentRequiredError.new("Your credit balance is too low") => [ :setup, :error, "ModelUnpaid" ],
    RubyLLM::Error.new("model 'qwen3:8b' not found", response: Answer.new(404, "")) => [ :setup, :error, "ModelMissing" ],
    RubyLLM::ContextLengthExceededError.new("prompt is too long") => [ :context_full, :error, "ContextOverflow" ]
  }.each do |error, (reason, severity, reported)|
    test "#{error.class.name.demodulize} (#{error.message.truncate(30)}) reads as #{reason} and is reported as #{reported}" do
      streams = nil
      report = assert_error_reported("Assistant::ReplyJob::Trouble::#{reported}".constantize) do
        streams = streamed { perform_with(FakeChat.new(@chat, error: error)) }
      end

      assert_includes streams, I18n.t("assistant.errors.#{reason}")
      assert_equal reason.to_s, @chat.reply_failures.sole.reason
      assert_equal severity, report.severity
      assert_same error, report.error.cause
      assert_not_includes report.error.message, error.message, "the same message every time, so a problem is one entry"
    end
  end

  test "anything else is a bug, reported as it is" do
    report = assert_error_reported(NoMethodError) { perform_with(FakeChat.new(@chat, error: NoMethodError.new("undefined method 'id' for nil"))) }

    assert_equal :error, report.severity
    assert_equal "failed", @chat.reply_failures.sole.reason
  end

  test "a reply queued for a message that was given up on doesn't run, and leaves the chat as it is" do
    claimed_at = @chat.replying_since
    @chat.release_reply!(claimed_at)
    travel 1.second
    @chat.claim_reply!

    swapping(Assistant::BookkeeperAgent, :for, ->(_chat) { flunk "a reply nobody waits for any more" }) do
      Assistant::ReplyJob.perform_now(@chat, claimed_at)
    end

    assert_predicate @chat.reload, :replying?, "the newer message's claim stands"
  end

  test "a chat deleted while its reply waits leaves nothing to do, and no error" do
    Assistant::ReplyJob.perform_later(@chat, @chat.replying_since)
    @chat.destroy!

    assert_no_error_reported { perform_enqueued_jobs(only: Assistant::ReplyJob) }
  end

  test "a reply that comes leaves no failure behind" do
    perform_with(FakeChat.new(@chat))

    assert_empty @chat.reply_failures
  end

  test "an empty answer is retried once, then reported instead of silence" do
    streams = streamed { perform_with(FakeChat.new(@chat, answers: [ "", "" ])) }

    assert_equal Assistant::Notes.render(:ran_out), note.call
    assert_includes streams, I18n.t("assistant.errors.no_answer")
    assert_empty @chat.assistant_messages.where(role: "system"), "notes never take the system role"
  end

  test "a model that thought until the output cap gets one more try" do
    perform_with(FakeChat.new(@chat, answers: [ "", "Saved the purchases." ]))

    assert_equal [ "Saved the purchases." ], @chat.visible_messages.where(role: "assistant").pluck(:content)
  end

  test "a reply that writes tool calls as text is dropped and retried once" do
    pseudo = "### Function Calls\n```python\nset_reference_ranges(ranges=[{\"analyte\": \"Cobalamin\"}])\n```"
    log = logged { perform_with(FakeChat.new(@chat, answers: [ pseudo, "Saved the Cobalamin range." ])) }

    assert_includes log, "[assistant] chat=#{@chat.id} retrying"
    assert_not_includes log, "Cobalamin", "the dropped reply's words stay out of the log"
    replies = @chat.visible_messages.where(role: "assistant").pluck(:content)
    assert_equal [ "Saved the Cobalamin range." ], replies
    assert_equal Assistant::Notes.render(:pseudo_call), note.call
    retried = @chat.assistant_messages.where(role: "assistant", hidden: true).sole
    assert_equal pseudo, retried.content, "the dropped reply is kept for the trace"
    assert_match(/\A\(retried\) ### Function Calls/, Assistant::Trace.new(@chat).turns.last.steps.find { |step| step.kind == :reply }.text)
  end

  test "a reply after a failed tool call is dropped and the model is told to fix the call" do
    perform_with(FakeChat.new(@chat, answers: [ "Please send the values as an array.", "Saved the Calcium range." ],
                                     tool_results: [ [ { ok: false, error: "unknown fields Calcium" } ], [ { ok: true, data: {} } ] ]))

    assert_equal [ "Saved the Calcium range." ], @chat.visible_messages.where(role: "assistant").pluck(:content)
    assert_match "unknown fields Calcium", note.call
  end

  test "after a tool stopped a failed-call loop, the model's explanation stands" do
    stop = { ok: false, error: "Stop: share already failed this way this turn (nobody called Giulia).", stop: true }
    perform_with(FakeChat.new(@chat, answers: [ "I couldn't find Giulia in the household — who did you mean?" ],
                                     tool_results: [ [ { ok: false, error: "nobody called Giulia" }, stop ] ]))

    assert_equal [ "I couldn't find Giulia in the household — who did you mean?" ], @chat.visible_messages.where(role: "assistant").pluck(:content)
    assert_empty @chat.assistant_messages.where(hidden: true)
  end
end
