# frozen_string_literal: true

# One of each record a route can name, all Alice's (profiles(:alice)), with
# Bob (profiles(:bob)) as the housemate she shares and links with, and the
# value each part of a route takes. The tenancy test asks for them as
# someone of another household; the forms test opens them as Alice.
# Expects @alice, @bob and @day.
module AlicesRecords
  # The value a route's part takes: one of Alice's records (or a name of
  # the admin's, for the routes only an admin may reach).
  def route_value(controller, part)
    key = "#{controller}##{part}"
    case key
    when "days#date", "day_completions#date" then @day.iso8601
    when "link_grants#event_type" then "Task"
    when "assistant/settings#provider" then "anthropic"
    when "assistant/evals/scenarios#name" then "appointments"
    when "assistant/evals/runs#id" then "20260926-120000-qwen3"
    when "message_pictures#id", "assistant/attachments#id" then 1
    else @records.fetch(key) { @records.fetch(part.to_s) { flunk "#{key}: say which of Alice's records it names" } }.id
    end
  end

  def build_alices_records
    task = task!(profile: @alice, date: @day)
    link = link!(@alice, @bob)
    held = Links::Approvals::Hold.call(requester: @bob, record: task, kind: :complete)
    collection = Collection.create!(profile: @alice, name: "B12", section: "healthcare")
    recipe = Recipe.create!(profile: @alice, name: "Soup")
    list = GroceryList.create!(profile: @alice, name: "Saturday")
    milk = list.grocery_list_items.create!(ingredient: pantry_ingredient(@alice, "Milk", quantity: 1))
    book = Book.create!(profile: @alice, title: "Dune", author: "Frank Herbert")
    file = keep_file(@alice)
    analyte = Analyte.create!(profile: @alice, name: "Ferritin")
    purchase = supply_purchase!(profile: @alice, name: "Needles")
    rice = pantry_ingredient(@alice, "Rice", quantity: 2)
    invitation = Profile.invite!({ email: "erin@example.com", household: households(:example) }, @alice) { _1.skip_invitation = true }
    conversation = Conversation.household_conversation(households(:example))
    message = send_message(conversation, @alice, "hi")
    chat = assistant_chat(@alice)
    notification = Notification.create!(profile: @alice, kind: :shared, subject: recipe, subject_title: "Soup")
    change_set = Assistant::ChangeSet.create!(chat: chat, profile: @alice, status: :applied, applied_at: Time.current, operations: [], undo_log: [])

    @records = {
      "id" => task, "event_id" => task.event, "tasks#id" => task,
      "links#id" => link, "link_id" => link,
      "link_approvals#id" => held, "link_approval_id" => held,
      "household_invitations#id" => invitation, "household_id" => households(:example),
      "household_members#id" => @bob, "household_member_id" => @bob,
      "appointments#id" => appointment!(profile: @alice, date: @day), "medications#id" => medication!(profile: @alice, date: @day),
      "meals#id" => meal_on(@alice, @day, title: "Out"), "lab_test_results#id" => lab_result!(profile: @alice, date: @day),
      "transactions#id" => expense!(profile: @alice, date: @day, cents: 1000),
      "collection_id" => collection, "collections#id" => collection,
      "recipe_id" => recipe, "recipes#id" => recipe,
      "grocery_list_id" => list, "grocery_lists#id" => list,
      "grocery_list_items#id" => milk, "grocery_list_item_id" => milk,
      "book_id" => book, "books#id" => book,
      "upload_id" => file, "uploads#id" => file, "upload_links#id" => mint_link(file).first,
      "analytes#id" => analyte, "analyte_id" => analyte, "reference_ranges#id" => ReferenceRange.create!(analyte: analyte, unit: units(:mgdl), sex: :any, high: 300),
      "supplies#id" => purchase.supply, "supply_id" => purchase.supply, "supply_purchases#id" => purchase, "household_invitation_id" => invitation,
      "ingredients#id" => rice, "ingredient_id" => rice, "ingredient_purchases#id" => ingredient_purchase!(profile: @alice),
      "conversations#id" => conversation, "conversation_id" => conversation, "messages#id" => message, "message_id" => message,
      "notifications#id" => notification, "notification_id" => notification,
      "chat_id" => chat, "assistant/chats#id" => chat,
      "assistant/change_sets#id" => change_set, "change_set_id" => change_set
    }
    # A share of each kind, for the routes that stop sharing one.
    @records["shares#id"] = EventShare.create!(event: task.event, profile: @bob)
    [ CollectionShare.create!(collection: collection, profile: @bob), RecipeShare.create!(recipe: recipe, profile: @bob),
      GroceryListShare.create!(grocery_list: list, profile: @bob), BookShare.create!(book: book, profile: @bob),
      UploadShare.create!(upload: file, profile: @bob), @alice.bookshelf!.bookshelf_shares.create!(profile: @bob) ]
  end
end
