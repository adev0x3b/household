# frozen_string_literal: true

# Where the assistant's answer would have been, why there is none: pushed
# when the turn ends, and drawn again with the thread.
class Views::Assistant::Chats::ReplyFailureNotice < Views::Base
  def initialize(failure:)
    @failure = failure
  end

  def view_template
    render Views::Assistant::Chats::Notice.new(kind: :error, text: t("assistant.errors.#{@failure.reason}"))
  end
end
