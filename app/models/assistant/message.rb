# frozen_string_literal: true

class Assistant::Message < ApplicationRecord
  acts_as_message chat: :assistant_chat, chat_class: "Assistant::Chat"

  # Kept outside RubyLLM's own attachments, because the model may not read
  # images and RubyLLM would send them again on every later turn, which
  # raises RubyLLM::UnsupportedAttachmentError. LabReports::Ocr reads the
  # text out of them, and the chat shows them.
  has_many_attached :attachments

  # How much one message may carry. The composer and the controller both
  # hold the user to these, so they live with the message, not with either.
  # A lab report photographed as several screenshots is one message.
  MAX_LENGTH = 4000
  MAX_IMAGES = 5
  SUPPORTED_ATTACHMENT_TYPES = %w[image/jpeg image/png image/webp image/heic].freeze
  MAX_ATTACHMENT_SIZE = 10.megabytes

  validate :attachments_are_supported_images

  private

  def attachments_are_supported_images
    attachments.each do |attachment|
      unless attachment.content_type.in?(SUPPORTED_ATTACHMENT_TYPES)
        errors.add(:attachments, :not_an_image)
      end
      errors.add(:attachments, :too_large) if attachment.byte_size > MAX_ATTACHMENT_SIZE
    end
  end
end
