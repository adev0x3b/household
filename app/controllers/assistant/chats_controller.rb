# frozen_string_literal: true

class Assistant::ChatsController < ApplicationController
  include AssistantEnabled
  include SearchableIndex

  before_action :set_chat, only: [ :show, :edit, :update, :destroy ]

  # The assistant's own page opens the latest chat, or the list when
  # there is none yet.
  def latest
    authorize Assistant::Chat, :index?
    chat = policy_scope(Assistant::Chat).recent_first.first
    redirect_to chat ? assistant_chat_path(chat) : assistant_chats_path
  end

  def index
    chats = index_page(policy_scope(Assistant::Chat).search(search_query).recent_first)

    render_searchable_index(page: Views::Assistant::Chats::Index.new(chats: chats, query: search_query),
                            results: Views::Assistant::Chats::List.new(chats: chats, query: search_query))
  end

  def show
    authorize @chat
    debug_allowed = policy(@chat).debug?
    change_sets = @chat.change_sets.where.not(display: []).to_a
    render_page Views::Assistant::Chats::Show.new(chat: @chat, messages: @chat.visible_messages.with_attached_attachments.to_a,
                                                  change_sets: change_sets, targets: Assistant::ChangeSets::RowTargets.load(change_sets),
                                                  reply_failures: @chat.reply_failures.to_a,
                                                  messages_left: Assistant::MessageAllowance.new(current_profile.household).left,
                                                  attach: policy(@chat).attach?, debug_allowed: debug_allowed,
                                                  debug: (debug_trace if debug_allowed && params[:debug].present?))
  end

  def create
    authorize Assistant::Chat
    chat = Assistant::Chat.open_blank!(profile: current_profile, locale: I18n.locale)
    redirect_to assistant_chat_path(chat), status: :see_other
  end

  def edit
    authorize @chat, :update?
    render_modal(Views::Assistant::Chats::Modals::Form.new(chat: @chat), page: @chat)
  end

  def update
    authorize @chat
    if @chat.update(title: params.expect(assistant_chat: [ :title ])[:title].to_s.strip.presence)
      redirect_back_after_save(assistant_chat_path(@chat), notice: t("assistant.chats.notices.renamed"))
    else
      render turbo_stream: redraw_modal(Views::Assistant::Chats::Modals::Form.new(chat: @chat)), status: :unprocessable_content
    end
  end

  def destroy
    authorize @chat
    Assistant::Chats::Destroy.call(@chat)
    redirect_after_destroy(assistant_chat_path(@chat), list: assistant_chats_path, notice: t("assistant.chats.notices.destroyed"))
  end

  private

  # The chat as the model saw it (?debug=1), with what the panel shows.
  def debug_trace
    Views::Assistant::Chats::DebugTrace.new(chat: @chat, trace: Assistant::Trace.new(@chat), change_sets: @chat.change_sets.order(:id).to_a,
                                            prompt: Assistant::Context.new(@chat).to_prompt,
                                            admin: Admin::PlatformPolicy.new(current_profile, :platform).manage?)
  end

  def set_chat
    @chat = policy_scope(Assistant::Chat).find(params[:id])
  end
end
