# frozen_string_literal: true

# A thread of messages between people of one household: the household's own
# (everyone in it, named by anyone) or a direct one between two housemates.
# Who is in it, and how far each has read, is a ConversationParticipant;
# what was said is a Message.
#
#   Conversation.household_conversation(household) # made with its first member, everyone joined in
#   Conversation.direct_between(alice, bob)        # made on first use, one per pair
#   Conversation.accessible_by(profile)            # the ones they take part in
#
# Nothing crosses households: a direct conversation is between housemates
# (WithinHousehold), and the household one belongs to its household.
class Conversation < ApplicationRecord
  include EditedTogether

  NAME_LENGTH = 60

  belongs_to :household
  belongs_to :created_by, class_name: "Profile", optional: true
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :profile
  has_many :messages, dependent: :destroy

  enum :kind, { direct: 0, household: 1 }, validate: true

  normalizes :name, with: ->(value) { value.to_s.squish.presence }

  validates :name, length: { maximum: NAME_LENGTH }
  validates :name, absence: true, if: :direct?
  validates :direct_key, presence: true, uniqueness: true, if: :direct?
  validates :direct_key, absence: true, if: :household?

  scope :accessible_by, ->(profile) { where(id: ConversationParticipant.where(profile_id: profile.id).select(:conversation_id)) }
  scope :recent_first, -> { order(Arel.sql("conversations.last_message_at DESC NULLS LAST"), id: :desc) }

  # The household's conversation, made when its first member joins. Everyone
  # joined is in it: a member who came after it was made is added as they
  # join (Profiles::Join), with all its history.
  def self.household_conversation(household)
    conversation = find_by(household: household, kind: :household) || create!(household: household, kind: :household)
    conversation.sync_household_participants!
    conversation
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # The conversation between two housemates, made the first time either opens it.
  def self.direct_between(one, other)
    raise ArgumentError, "a conversation is between two different people" if one.id == other.id

    key = direct_key_for(one, other)
    find_by(direct_key: key) || transaction do
      create!(household: one.household, kind: :direct, direct_key: key, created_by: one).tap do |conversation|
        conversation.conversation_participants.create!(profile: one)
        conversation.conversation_participants.create!(profile: other)
      end
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(direct_key: key)
  end

  def self.direct_key_for(one, other) = [ one.id, other.id ].minmax.join(":")

  # Every joined member of the household takes part; who left (Profiles::Destroy) is gone already.
  def sync_household_participants!
    return unless household?

    missing = household.members.where.not(id: conversation_participants.select(:profile_id)).pluck(:id)
    return if missing.empty?

    now = Time.current
    ConversationParticipant.insert_all(missing.map { |profile_id| { conversation_id: id, profile_id: profile_id, joined_at: now, created_at: now, updated_at: now } },
                                       unique_by: [ :conversation_id, :profile_id ])
    conversation_participants.reset
  end

  def participant_for(profile) = conversation_participants.find { |p| p.profile_id == profile.id }

  def participant?(profile) = conversation_participants.any? { |p| p.profile_id == profile.id }

  # The other person of a direct conversation.
  def counterpart_of(profile) = direct? ? participants.find { |p| p.id != profile.id } : nil

  # What to call it for `viewer`: its name (the household's, until renamed) or the other person.
  def title_for(viewer)
    if household?
      name.presence || I18n.t("conversations.household.default_name", household: household.name)
    else
      counterpart_of(viewer)&.display_name || I18n.t("conversations.direct.gone")
    end
  end

  # A new message isn't an edit of the conversation, so a rename open
  # meanwhile still saves; and it lands whatever version this copy is at.
  def touch_last_message!(message)
    self.class.where(id: id).update_all_keeping_version(last_message_at: message.created_at, updated_at: Time.current)
  end

  # Messages `profile` hasn't seen yet, from others.
  def unread_count_for(profile)
    participant = participant_for(profile) or return 0
    messages.where.not(sender_id: profile.id).where("messages.id > ?", participant.last_read_message_id || 0).count
  end
end
