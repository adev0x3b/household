# frozen_string_literal: true

# Removes people with everything they kept: their records, shares,
# notifications and conversations, then the profiles themselves. What
# others kept about them stays, unlinked: a transfer loses its other side,
# a visit filed in their therapy is in none, a cost about their purchase is
# about nothing, an event shared with them is no longer, a household they
# owned has no owner until someone is named.
#
#   Profiles::Destroy.call(profile)        # one person
#   Profiles::Destroy.call(profiles)       # several, in one transaction
#
# Rows are deleted straight from the database in the order its foreign
# keys allow, with no callbacks: nothing is given back to stock that is
# going away too. What lives outside the database (a message's pictures,
# the bytes of a file) goes once the transaction has committed, so a
# removal that fails halfway leaves every file of what is still there.
# Households::Destroy uses it for a whole household.
module Profiles
  class Destroy
    def self.call(profiles) = new(Array(profiles).map(&:id)).call

    def initialize(ids)
      @ids = ids
    end

    def call
      return if @ids.empty?

      ActiveRecord::Base.transaction do
        delete_conversations
        delete_notifications
        delete_console_presses
        delete_links
        delete_series
        delete_pantry
        delete_library
        delete_files
        delete_healthcare_catalog
        delete_collections
        unlink_others
        Profile.where(id: @ids).delete_all
      end
    end

    private

    # Their chats with the assistant, with the photos sent to it once
    # committed; their messages and reactions; the direct conversations they
    # were half of, whole (nobody is left to talk in them). The household's
    # conversation keeps the others' words.
    def delete_conversations
      Assistant::Chats::Destroy.call(Assistant::Chat.where(profile_id: @ids))

      # Read first: once their places in them are gone, nothing says which they were.
      direct = Conversation.direct.where(id: ConversationParticipant.where(profile_id: @ids).select(:conversation_id)).ids
      messages = Message.where(sender_id: @ids).or(Message.where(conversation_id: direct))
      MessageReaction.where(message_id: messages.select(:id)).or(MessageReaction.where(profile_id: @ids)).delete_all
      delete_pictures(ActiveStorage::Attachment.where(record_type: "Message", record_id: messages.select(:id)))
      Message.where(id: messages.select(:id)).delete_all
      ConversationParticipant.where(conversation_id: direct).or(ConversationParticipant.where(profile_id: @ids)).delete_all
      Conversation.where(id: direct).delete_all
    end

    # The attachments' rows now, their blobs and files once nothing can roll back.
    def delete_pictures(attachments)
      blob_ids = attachments.pluck(:blob_id)
      attachments.delete_all
      after_commit { ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge_later) }
    end

    # What reached them or came from them under the bell, and the devices
    # they got it on.
    def delete_notifications
      Notification.where(profile_id: @ids).or(Notification.where(actor_id: @ids)).delete_all
      PushSubscription.where(profile_id: @ids).delete_all
    end

    # What they pressed on the delivery console: GitHub keeps each run's own
    # record of who asked.
    def delete_console_presses = Delivery::Request.where(profile_id: @ids).delete_all

    # Their links to housemates, either side: what each let the other do,
    # and the requests waiting on it.
    def delete_links
      links = Link.where(requester_id: @ids).or(Link.where(addressee_id: @ids)).select(:id)
      LinkApproval.where(link_id: links).delete_all
      LinkGrant.where(link_id: links).delete_all
      Link.where(id: links).delete_all
    end

    # Their series, with every day and everything that hangs off them
    # (Events::Purge: the costs others attached to them go on unattached),
    # and what their supplies were drawn for on others' days.
    def delete_series
      SupplyConsumption.where(supply_id: Supply.where(profile_id: @ids).select(:id)).delete_all
      Events::Purge.call(Event.where(profile_id: @ids))
    end

    def delete_pantry
      lists = GroceryList.where(profile_id: @ids).select(:id)
      recipes = Recipe.where(profile_id: @ids).select(:id)

      IngredientPurchase.where(profile_id: @ids).delete_all
      GroceryListItem.where(grocery_list_id: lists).delete_all
      GroceryListShare.where(grocery_list_id: lists).or(GroceryListShare.where(profile_id: @ids)).delete_all
      GroceryList.where(id: lists).delete_all
      MealRecipe.where(recipe_id: recipes).delete_all
      RecipeIngredient.where(recipe_id: recipes).delete_all
      RecipeStep.where(recipe_id: recipes).delete_all
      RecipeShare.where(recipe_id: recipes).or(RecipeShare.where(profile_id: @ids)).delete_all
      Recipe.where(id: recipes).delete_all
      Ingredient.where(profile_id: @ids).delete_all
    end

    # Books, their shares, and the shelves shared as a whole.
    def delete_library
      books = Book.where(profile_id: @ids).select(:id)
      shelves = Bookshelf.where(profile_id: @ids).select(:id)

      BookShare.where(book_id: books).or(BookShare.where(profile_id: @ids)).delete_all
      Book.where(id: books).delete_all
      BookshelfShare.where(bookshelf_id: shelves).or(BookshelfShare.where(profile_id: @ids)).delete_all
      Bookshelf.where(id: shelves).delete_all
    end

    # Their files, with the shares, links and trail of each; what others
    # shared with them. The bytes go once the rows are gone for good.
    def delete_files
      uploads = Upload.where(profile_id: @ids)
      keys = uploads.pluck(:key)
      ids = uploads.select(:id)

      UploadActivity.where(upload_id: ids).or(UploadActivity.where(profile_id: @ids)).delete_all
      UploadLink.where(upload_id: ids).delete_all
      UploadShare.where(upload_id: ids).or(UploadShare.where(profile_id: @ids)).delete_all
      Upload.where(id: ids).delete_all
      after_commit { keys.each { |key| Uploads::Storage.delete(key) } }
    end

    # Their supplies with every purchase of them, a housemate's restock too,
    # and what they bought of a housemate's supply. A dose drawn from one of
    # those purchases keeps what it drew, from no batch in particular.
    def delete_healthcare_catalog
      analytes = Analyte.where(profile_id: @ids).select(:id)
      supplies = Supply.where(profile_id: @ids).select(:id)
      purchases = SupplyPurchase.where(profile_id: @ids).or(SupplyPurchase.where(supply_id: supplies)).select(:id)

      SupplyUse.where(supply_id: supplies).delete_all
      SupplyConsumption.where(supply_purchase_id: purchases).update_all(supply_purchase_id: nil)
      Transaction::Details.where(about_type: "SupplyPurchase", about_id: purchases).update_all(about_type: nil, about_id: nil)
      SupplyPurchase.where(id: purchases).delete_all
      Supply.where(id: supplies).delete_all
      ReferenceRange.where(analyte_id: analytes).delete_all
      AnalyteAlias.where(profile_id: @ids).delete_all
      Analyte.where(id: analytes).delete_all
    end

    # What they had of others' series — shares, their reminders — then
    # their collections. What a housemate filed in one of those stays the
    # housemate's, in no collection.
    def delete_collections
      collections = Collection.where(profile_id: @ids).select(:id)

      EventShare.where(profile_id: @ids).delete_all
      reminders = EventReminder.where(profile_id: @ids)
      EventReminderDelivery.where(event_reminder_id: reminders.select(:id)).delete_all
      reminders.delete_all
      Event.where(collection_id: collections).update_all(collection_id: nil)
      SupplyPurchase.where(collection_id: collections).update_all(collection_id: nil)
      CollectionShare.where(collection_id: collections).or(CollectionShare.where(profile_id: @ids)).delete_all
      Collection.where(id: collections).delete_all
    end

    def after_commit(&) = ActiveRecord::Base.current_transaction.after_commit(&)

    # What others kept about them. The database's own keys let go of the
    # rest: who owned a household, started a conversation, last saved a
    # setting or something housemates edit together, and how far a housemate
    # had read.
    def unlink_others
      Transaction::Details.where(counterparty_profile_id: @ids).update_all(counterparty_profile_id: nil)
      Profile.where(invited_by_type: "Profile", invited_by_id: @ids).update_all(invited_by_id: nil, invited_by_type: nil)
    end
  end
end
