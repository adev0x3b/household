# frozen_string_literal: true

class Assistant::ReplyJob
  # A turn's tool calls, watched through the model chat's callbacks: how
  # many were made (the turn is cancelled past MAX_TOOL_CALLS), which
  # failed, whether a tool stopped a failed-call loop, and which models
  # answered (a provider fallback would differ from the chat's model).
  class Calls
    attr_reader :errors, :served

    def initialize(llm)
      @count = 0
      @errors = []
      @stopped = false
      @served = Set.new
      llm.before_tool_call { llm.cancel if (@count += 1) > MAX_TOOL_CALLS }
      llm.after_tool_result { |result| record(result) if result.is_a?(Hash) }
      llm.after_message { |message| @served << message.model.to_s if message.model.present? }
    end

    def too_many? = @count > MAX_TOOL_CALLS

    # Calls failed and no tool told the model to stop and explain instead.
    def failed_unexplained? = @errors.any? && !@stopped

    # A new try starts with nothing failed.
    def forget_errors = @errors.clear

    private

    def record(result)
      @errors << result[:error] if result[:ok] == false
      @stopped ||= result[:stop]
    end
  end
end
