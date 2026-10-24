# frozen_string_literal: true

# One person's emoji on one message: once per emoji per person (a second
# tap takes it back, MessageReactionsController). Any single emoji is
# accepted, not only the quick ones the picker offers (QUICK).
class MessageReaction < ApplicationRecord
  QUICK = %w[👍 ❤️ 😂 😮 😢 🙏 🎉 👀].freeze
  # One grapheme that is a pictograph: "👍", "👍🏽", "❤️", a flag — never "a" or "1".
  EMOJI = /\A\X\z/

  belongs_to :message
  belongs_to :profile

  validates :emoji, presence: true, length: { maximum: 32 }, uniqueness: { scope: [ :message_id, :profile_id ] }
  validate :emoji_is_one_emoji
  validate :reacts_as_a_participant

  def self.emoji?(value)
    value = value.to_s
    value.match?(EMOJI) && value.match?(/\p{Extended_Pictographic}|\p{Emoji_Presentation}/)
  end

  private

  def emoji_is_one_emoji
    errors.add(:emoji, :invalid) if emoji.present? && !self.class.emoji?(emoji)
  end

  def reacts_as_a_participant
    return if message.nil? || profile.nil?

    errors.add(:profile, :not_a_participant) unless message.conversation.participant?(profile)
    errors.add(:message, :deleted) if message.deleted?
  end
end
