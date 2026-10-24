# frozen_string_literal: true

# One message in a conversation: text, pictures, or both, with its emoji
# reactions. Sent through Messages::Send (which also tells the others);
# unsent by its sender with #unsend!, which empties it but keeps its place.
#
# `client_id` is minted by the composer (a UUID): the same message sent
# twice by a flaky connection is saved once (Messages::Send).
class Message < ApplicationRecord
  BODY_LENGTH = 4000
  MAX_IMAGES = 4
  MAX_IMAGE_SIZE = 10.megabytes
  IMAGE_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
  URL = %r{https?://[^\s<>"']+}

  belongs_to :conversation
  belongs_to :sender, class_name: "Profile"
  has_many :message_reactions, dependent: :destroy
  # What a page shows: shrunk and stripped of its metadata (a phone's
  # location and camera data never leave the original, which only its
  # signed URL opens), made right after the send (preprocessed) so the
  # first reader doesn't wait for it.
  has_many_attached :images do |attachable|
    attachable.variant :shown, resize_to_limit: [ 1200, 1200 ], saver: { strip: true }, preprocessed: true
  end

  normalizes :body, with: ->(value) { value.to_s.strip.presence }

  validates :client_id, presence: true, uniqueness: { scope: :sender_id }
  validates :body, length: { maximum: BODY_LENGTH }
  validate :has_something_to_say, on: :create
  validate :images_are_pictures
  validates_within_household :sender, of: :conversation
  validate :sender_takes_part, on: :create

  scope :oldest_first, -> { order(:id) }
  scope :newest_first, -> { order(id: :desc) }
  scope :before, ->(id) { id.present? ? where("messages.id < ?", id.to_i) : all }
  scope :with_everything, -> { includes(:sender, images_attachments: :blob, message_reactions: :profile) }

  def deleted? = deleted_at.present?

  # Empties it in place: what others saw stays a placeholder, nothing of it is kept.
  def unsend!
    transaction do
      message_reactions.delete_all
      images.purge_later
      update!(body: nil, deleted_at: Time.current)
    end
  end

  # Reactions grouped by emoji, in the order they were first given:
  # [ [ "👍", [ profile, … ] ], … ]
  def reactions_by_emoji
    message_reactions.sort_by(&:id).group_by(&:emoji).map { |emoji, reactions| [ emoji, reactions.map(&:profile) ] }
  end

  # Who said it and what, as a list or a notification shows it.
  def line(name: sender.display_name) = I18n.t("conversations.message.line", name: name, text: preview)

  # The one line a list or a notification shows.
  def preview
    return I18n.t("conversations.message.deleted") if deleted?
    return body.truncate(80) if body.present?

    I18n.t("conversations.message.picture", count: images.size)
  end

  private

  def has_something_to_say
    errors.add(:body, :blank) if body.blank? && images.blank?
  end

  def images_are_pictures
    errors.add(:images, :too_many, max: MAX_IMAGES) if images.size > MAX_IMAGES
    images.each do |image|
      errors.add(:images, :not_a_picture) unless image.content_type.in?(IMAGE_TYPES)
      errors.add(:images, :too_large, max: ActiveSupport::NumberHelper.number_to_human_size(MAX_IMAGE_SIZE)) if image.byte_size.to_i > MAX_IMAGE_SIZE
    end
  end

  def sender_takes_part
    return if conversation.nil? || sender.nil?

    errors.add(:sender, :not_a_participant) unless conversation.participant?(sender)
  end
end
