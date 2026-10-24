# frozen_string_literal: true

module Assistant
  # What a model wrote, split into what it thought and what it said. Some
  # models think aloud between <think> tags before they answer; some leave
  # the opening tag to their chat template, so the text starts mid-thought;
  # and one cut off while thinking never closes the tag. None of the
  # thinking is part of the answer.
  #
  #   reply = Assistant::ModelReply.new("<think>Two tasks match.</think>Which one?")
  #   reply.answer    # => "Which one?"
  #   reply.thinking  # => "Two tasks match."
  class ModelReply
    UNOPENED = %r{\A((?:(?!<think>).)*?)</think>}m
    BLOCK = %r{<think>(.*?)(?:</think>|\z)}m

    def initialize(text)
      @text = text.to_s
    end

    def answer = @text.sub(UNOPENED, "").gsub(BLOCK, "").strip

    def thinking
      thoughts = [ @text[UNOPENED, 1], *@text.sub(UNOPENED, "").scan(BLOCK).flatten ]
      thoughts.compact.map(&:strip).compact_blank.join("\n\n")
    end
  end
end
