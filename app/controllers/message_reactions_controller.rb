# frozen_string_literal: true

# An emoji on a message: given (POST) or taken back (DELETE) by the person
# tapping it. Both answer with the message's reactions region, and push it
# to everyone (never the whole bubble: its pictures would load again).
class MessageReactionsController < ApplicationController
  rate_limit_per_person to: 60, within: 1.minute

  before_action :set_message

  def create
    authorize @message, :react?

    reaction = @message.message_reactions.find_or_initialize_by(profile: current_profile, emoji: params[:emoji].to_s)
    return refuse(reaction.errors.full_messages.to_sentence) if reaction.new_record? && !reaction.save

    answer_with_reactions
  end

  def destroy
    authorize @message, :react?

    @message.message_reactions.where(profile: current_profile, emoji: params[:emoji].to_s).destroy_all
    answer_with_reactions
  end

  private

  def set_message
    @message = Message.joins(:conversation).merge(Conversation.accessible_by(current_profile)).includes(conversation: :conversation_participants).find(params[:message_id])
  end

  def answer_with_reactions
    Conversations::Broadcaster.later(:reactions_changed, @message)
    message = Message.with_everything.find(@message.id)
    render turbo_stream: turbo_stream.update(Views::Conversations::Reactions.dom_id(message),
                                             Views::Conversations::Reactions.new(message: message, viewer: current_profile))
  end
end
