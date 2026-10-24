# frozen_string_literal: true

# The household's messages: the list of conversations, one conversation's
# page (its thread, live for everyone in it), opening the one with a
# housemate, renaming the household's, and paging back through older
# messages. What the reader has seen is ConversationReadReceiptsController's.
class ConversationsController < ApplicationController
  include KeepsWhatWasTyped

  PAGE = 50

  before_action :set_conversation, only: %i[show edit update older]

  def index
    conversations = policy_scope(Conversation).includes(:participants, :conversation_participants)
    household_conversation = conversations.household.take!
    direct = conversations.direct.recent_first.to_a
    without = current_profile.housemates.by_name.reject { |mate| direct.any? { |c| c.participant?(mate) } }

    summaries = Conversations::Summaries.new(current_profile, [ household_conversation, *direct ])

    render_page Views::Conversations::Index.new(household_conversation: household_conversation, direct: direct, housemates_without: without, summaries: summaries,
                                                viewer: current_profile)
  end

  # The conversation with the housemate named, made the first time: a
  # press, because a GET would make it on a hovered row Turbo prefetches,
  # for both people's lists.
  def create
    authorize Conversation
    housemate = current_profile.housemates.find(params[:profile_id])
    redirect_to conversation_path(Conversation.direct_between(current_profile, housemate)), status: :see_other
  end

  def show
    authorize @conversation

    # Reads nothing: a GET can be Turbo prefetching a hovered row. The page
    # posts its read receipt once it is seen (conversation_controller.js).
    messages = @conversation.messages.with_everything.newest_first.limit(PAGE).to_a.reverse
    more = messages.any? && @conversation.messages.before(messages.first.id).exists?

    render_page Views::Conversations::Show.new(conversation: @conversation, messages: messages, more: more,
                                               readers: Conversations::Readers.new(@conversation).excluding(current_profile), viewer: current_profile)
  end

  def edit
    authorize @conversation, :update?

    render_modal(Views::Conversations::Modals::Rename.new(conversation: @conversation), page: @conversation)
  end

  def update
    authorize @conversation

    if @conversation.edit_as(current_profile, typed: typed_fields(@conversation, conversation_params)) { @conversation.update(conversation_params) }
      Conversations::Broadcaster.later(:renamed, @conversation)
      render turbo_stream: [ close_modal, toast(:success, t("conversations.notices.renamed")) ]
    else
      render turbo_stream: redraw_modal(Views::Conversations::Modals::Rename.new(conversation: @conversation)), status: :unprocessable_content
    end
  end

  # The page of messages before `before`, put above the ones shown.
  def older
    authorize @conversation

    messages = @conversation.messages.with_everything.before(params[:before]).newest_first.limit(PAGE).to_a.reverse
    more = messages.any? && @conversation.messages.before(messages.first.id).exists?

    render turbo_stream: [
      turbo_stream.replace(Views::Conversations::Older.dom_id(@conversation),
                           Views::Conversations::Older.new(conversation: @conversation, before: messages.first&.id, more: more)),
      turbo_stream.after(Views::Conversations::Older.dom_id(@conversation),
                         Views::Conversations::Bubbles.new(messages: messages, viewer: current_profile))
    ]
  end

  private

  def set_conversation
    @conversation = policy_scope(Conversation).includes(:household, :participants, :conversation_participants).find(params[:id])
  end

  def conversation_params = params.expect(conversation: %i[name lock_version])
end
