# frozen_string_literal: true

# One chat between a profile and the assistant. Persistence of
# messages and tool calls is RubyLLM's (acts_as_chat); the agent's
# configuration lives in Assistant::BookkeeperAgent.
class Assistant::Chat < ApplicationRecord
  include Searchable

  acts_as_chat messages: :assistant_messages, message_class: "Assistant::Message", messages_foreign_key: :assistant_chat_id

  # A reply stuck longer than this (a crashed worker, or none running) no
  # longer blocks the chat, and Assistant::ReplyTimeoutJob says so.
  REPLY_TIMEOUT = 10.minutes

  belongs_to :profile
  has_many :change_sets, class_name: "Assistant::ChangeSet", foreign_key: :assistant_chat_id, dependent: :destroy, inverse_of: :chat
  has_many :reply_failures, class_name: "Assistant::ReplyFailure", foreign_key: :assistant_chat_id, dependent: :delete_all, inverse_of: :chat

  TITLE_MAX_LENGTH = 120

  validates :title, length: { maximum: TITLE_MAX_LENGTH }

  scope :recent_first, -> { order(updated_at: :desc, id: :desc) }
  scope :untouched, -> { where.missing(:assistant_messages) }
  searchable_by :title

  # Local models (Ollama) are not in RubyLLM's model registry.
  after_initialize { self.assume_model_exists = true }

  def self.start!(profile:, locale: I18n.locale, time_zone: nil)
    create!(profile: profile, locale: locale.to_s, time_zone: time_zone.presence,
            model: Assistant.model, provider: Assistant.provider)
  end

  # The credentials configured now, never the ones read at boot. RubyLLM
  # builds the chat and checks the provider's key with this context, so it
  # must be set before #to_llm.
  def context
    super || (self.context = Assistant.llm_context)
  end

  # A chat started on another model moves to the one configured
  # now, so the household has one assistant. It runs before #to_llm, so the
  # old provider is never built.
  def follow_settings!
    return if model_id == Assistant.model && provider.to_s == Assistant.provider.to_s

    self.model = Assistant.model
    self.provider = Assistant.provider
    save!
  end

  # The profile's blank chat if they already have one (so spamming
  # "new" never piles up empty chats), else a fresh one.
  def self.open_blank!(profile:, locale: I18n.locale, time_zone: nil)
    where(profile: profile).untouched.recent_first.first || start!(profile: profile, locale: locale, time_zone: time_zone)
  end

  # Atomically claims the chat for one reply job; false when one is running.
  def claim_reply!
    claimed = self.class.where(id: id)
      .where("replying_since IS NULL OR replying_since < ?", REPLY_TIMEOUT.ago)
      .update_all(replying_since: Time.current, cancelled: false)
    reload if claimed == 1
    claimed == 1
  end

  # Frees the chat. Given when the reply was claimed, only from that claim:
  # a reply never frees a chat that was freed and claimed again meanwhile.
  # True when it was freed.
  def release_reply!(claimed_at = nil)
    claims = self.class.where(id: id)
    claims = claims.where(replying_since: claimed_at) if claimed_at
    released = claims.update_all(replying_since: nil) == 1
    self.replying_since = nil if released
    released
  end

  def replying?
    replying_since.present? && replying_since > REPLY_TIMEOUT.ago
  end

  # The user's messages and the assistant's replies, without the app's notes
  # to the model or a reply the model tried again.
  def visible_messages
    assistant_messages.where(role: %w[user assistant], hidden: false).where.not(content: [ nil, "" ]).order(:created_at, :id)
  end

  # How the app speaks to the model inside the chat: a user-role
  # message, hidden from the thread, that opens by saying who wrote it.
  NOTE_PREFIX = "[Note from the app, not from the user] "

  def self.note_text(text) = text.start_with?(NOTE_PREFIX) ? text : NOTE_PREFIX + text

  # Something that happened outside the chat (a button press, a
  # photo that couldn't be read) that the model must know next turn. It is
  # not a system message, because providers lift those out of the
  # chat: the note would lose its place in the dialogue and gain an
  # authority the app's events, let alone a document's text, must not have.
  def note_for_model!(text)
    assistant_messages.create!(role: "user", content: self.class.note_text(text), hidden: true)
  end

  # Hides the newest message of a role (a note just added through RubyLLM, a
  # reply being tried again): the trace keeps it, the thread doesn't.
  def hide_last!(role)
    assistant_messages.where(role: role.to_s).order(:id).last&.update_columns(hidden: true)
  end

  def time_zone_or_default
    ActiveSupport::TimeZone[time_zone.to_s] || Time.zone
  end
end
