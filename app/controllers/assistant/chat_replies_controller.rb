# frozen_string_literal: true

# The reply the assistant is writing in a chat, stopped by the composer's
# stop button. It stops at its next step rather than at once, because
# RubyLLM checks the chat's `cancelled` flag between steps.
class Assistant::ChatRepliesController < ApplicationController
  include AssistantEnabled

  def destroy
    chat = policy_scope(Assistant::Chat).find(params[:chat_id])
    authorize chat, :update?

    chat.cancel if chat.replying?
    head :no_content
  end
end
