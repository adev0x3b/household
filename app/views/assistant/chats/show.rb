# frozen_string_literal: true

# One chat with the assistant, kept live over its signed
# Turbo stream: Assistant::Broadcaster and Assistant::MessagesController
# add to its thread.
class Views::Assistant::Chats::Show < Views::Base
  include Phlex::Rails::Helpers::TurboStreamFrom

  THREAD_ID = "assistant-thread"

  # Gone with the first message, which Assistant::MessagesController appends.
  WELCOME_ID = "assistant-welcome"

  # messages: the chat's visible messages with their photos; change_sets:
  # those with something to show, and what their rows open
  # (Assistant::ChangeSets::RowTargets); reply_failures: the turns that
  # ended without an answer (Assistant::ReplyFailure). messages_left and
  # attach: what the composer says and offers (Views::Assistant::Chats::Composer).
  # debug_allowed: whether the viewer may open the trace panel (an admin,
  # or anyone in development); debug: the panel, when the viewer asked for
  # it (Views::Assistant::Chats::DebugTrace), else nil.
  def initialize(chat:, messages:, change_sets:, targets:, reply_failures:, messages_left:, attach:, debug_allowed: false, debug: nil)
    @chat = chat
    @messages = messages
    @change_sets = change_sets
    @targets = targets
    @reply_failures = reply_failures
    @messages_left = messages_left
    @attach = attach
    @debug_allowed = debug_allowed
    @debug = debug
  end

  def page_title = title

  # A new chat and renaming this one are the bar's; the list of
  # them, the trace and deleting fold behind its "more".
  def navbar_controls
    Components::PageControls.new(actions: [
      Components::Action.new(href: routes.assistant_chats_path, icon: "fa-plus", label: t("assistant.chats.new"), method: :post),
      Components::Action.new(href: routes.edit_assistant_chat_path(@chat), icon: "fa-pen", label: t("assistant.chats.rename"), turbo_stream: true),
      (debug_toggle if @debug_allowed),
      Components::Action.new(href: routes.assistant_chat_path(@chat), icon: "fa-trash", label: t("assistant.chats.delete"), method: :delete,
                             confirm: t("assistant.chats.confirm_destroy", title: title), danger: true)
    ].compact)
  end

  def view_template
    div(class: "assistant", data: { controller: "assistant-chat" }) do
      turbo_stream_from @chat
      header
      # A log, so a screen reader reads what is added as it arrives: the
      # reader's message, the assistant's answer, what it changed.
      div(id: THREAD_ID, class: "assistant__thread", role: "log", data: { assistant_chat_target: "thread" }) do
        render @debug if @debug
        timeline.empty? ? welcome : timeline.each { |item| render item }
        render Views::Assistant::Chats::Reply.new(text: nil) if @chat.replying?
      end
      render Views::Assistant::Chats::Composer.new(chat: @chat, busy: @chat.replying?, messages_left: @messages_left, attach: @attach)
    end
  end

  private

  def title = @chat.title.presence || t("assistant.chats.new_title")

  def debug_toggle
    Components::Action.new(href: routes.assistant_chat_path(@chat, debug: (@debug ? nil : 1)), icon: "fa-bug",
                           label: t(@debug ? "assistant.debug.hide" : "assistant.debug.show"), active: @debug)
  end

  # The page's buttons are the top bar's: the header holds the title and the
  # way back to the list.
  def header
    div(class: "assistant__header") do
      render Components::PageHeader.new(title: title, back_href: assistant_chats_path, back_label: t("assistant.chats.all"))
    end
  end

  def welcome
    div(id: WELCOME_ID, class: "assistant__welcome") do
      render Components::Icon.new("fa-feather-pointed", class: "assistant__welcome-icon")
      p(class: "assistant__welcome-text") { t("assistant.thread.welcome") }
      ul(class: "assistant__examples") do
        t("assistant.thread.examples").each { |example| li { example } }
      end
    end
  end

  # Messages, change sets and the turns that failed, in the order they happened.
  def timeline
    @timeline ||= begin
      messages = @messages.map do |m|
        [ m.created_at, Views::Assistant::Chats::MessageBubble.new(role: m.role, content: m.content, attachments: m.attachments) ]
      end
      changes = @change_sets.map { |set| [ set.created_at, Views::Assistant::Chats::ChangeSetCard.new(change_set: set, targets: @targets) ] }
      failures = @reply_failures.map { |failure| [ failure.created_at, Views::Assistant::Chats::ReplyFailureNotice.new(failure: failure) ] }
      (messages + changes + failures).sort_by(&:first).map(&:last)
    end
  end
end
