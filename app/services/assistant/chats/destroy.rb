# frozen_string_literal: true

module Assistant
  module Chats
    # Deletes chats with the assistant and everything in them, in a
    # statement per table. Destroying them would run RubyLLM's callbacks
    # for every message, each reading and changing its own tool calls and
    # usage, so a long chat would cost a few queries per message.
    # The photos sent in them go once the deletion has committed.
    #
    #   Assistant::Chats::Destroy.call(chat)
    #   Assistant::Chats::Destroy.call(Assistant::Chat.where(profile_id: ids))   # Profiles::Destroy
    class Destroy
      def self.call(chats) = new(chats).call

      def initialize(chats)
        @chats = chats.is_a?(Assistant::Chat) ? Assistant::Chat.where(id: chats.id) : chats
      end

      def call
        ActiveRecord::Base.transaction do
          chats = @chats.select(:id)
          messages = Assistant::Message.where(assistant_chat_id: chats).select(:id)

          RubyLLM::ActiveRecord::ToolCall.where(message_type: Assistant::Message.name, message_id: messages).delete_all
          RubyLLM::ActiveRecord::Usage.where(chat_type: Assistant::Chat.name, chat_id: chats).delete_all
          Assistant::ChangeSet.where(assistant_chat_id: chats).delete_all
          Assistant::ReplyFailure.where(assistant_chat_id: chats).delete_all
          delete_photos(ActiveStorage::Attachment.where(record_type: Assistant::Message.name, record_id: messages))
          Assistant::Message.where(assistant_chat_id: chats).delete_all
          Assistant::Chat.where(id: chats).delete_all
        end
      end

      private

      def delete_photos(attachments)
        blob_ids = attachments.pluck(:blob_id)
        attachments.delete_all
        ActiveRecord::Base.current_transaction.after_commit { ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge_later) }
      end
    end
  end
end
