# frozen_string_literal: true

# A turn that ended without the assistant's answer, and why. The thread
# shows it where the answer would have been, after a reload as well as
# live, so a question is never left looking unanswered for no reason.
class Assistant::ReplyFailure < ApplicationRecord
  belongs_to :chat, class_name: "Assistant::Chat", foreign_key: :assistant_chat_id, inverse_of: :reply_failures

  enum :reason, { failed: 0, unreachable: 1, cancelled: 2, too_many_steps: 3, no_answer: 4, rate_limited: 5, setup: 6, context_full: 7, stalled: 8 }
end
