# frozen_string_literal: true

# A row of the example household in every table, together with the
# fixtures: what the tests read from the schema walk over. Each one asks for
# whatever is missing (a table the household keeps nothing in, a reference
# no row of it uses), and the missing row is added here, so all of them
# see it.
module EveryTable
  def give_the_example_household_a_row_everywhere
    alice, bob = profiles(:alice), profiles(:bob)
    chat = assistant_chat(alice)
    chat.assistant_messages.create!(role: "user", content: "hello").attachments.attach(picture_upload)
    Notification.create!(profile: bob, actor: alice, kind: :shared, subject: recipes(:roast_chicken), subject_title: "Soup")
    events(:groceries).event_reminders.create!(profile: bob, offset_minutes: 60).deliveries.create!(date: Date.current)
    push_subscription_for(bob)
    alice.bookshelf!.bookshelf_shares.create!(profile: bob)

    # Messages: a picture with a reaction, read by a housemate, and a direct conversation.
    household_conversation = Conversation.household_conversation(households(:example))
    picture = send_message(household_conversation, alice, "bye", images: [ picture_upload ])
    picture.message_reactions.create!(profile: bob, emoji: "👋")
    household_conversation.participant_for(bob).read_up_to!(picture)
    send_message(Conversation.direct_between(alice, bob), bob, "bye")

    link!(alice, bob)
    Links::Approvals::Hold.call(requester: bob, record: occurrences(:groceries_due), kind: :complete)

    # A file shared, and handed out by a link that has been used.
    file = keep_file(alice, name: "lease.txt")
    file.upload_shares.create!(profile: bob)
    file_link, _ = mint_link(file)
    UploadActivity.record(file, :downloaded, link: file_link)

    # The assistant: what it ran for a reply, what it cost, what it changed.
    reply = chat.assistant_messages.create!(role: "assistant", content: "Done")
    chat.reply_failures.create!(reason: :unreachable)
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call-1", name: "search_records", arguments: {})
    chat.ruby_llm_usages.create!(message: reply, model: "qwen3", provider: "ollama", operation: "chat", status: "succeeded",
                                 input_tokens: 10, output_tokens: 2)
    Assistant::ChangeSet.create!(chat: chat, profile: alice, status: :applied, applied_at: Time.current, operations: [], undo_log: [])
    AnalyteAlias.create!(profile: alice, analyte: analytes(:glucose), name: "Glicemia")
    ferritin = Analyte.create!(profile: alice, name: "Ferritin") # never measured, so nothing refuses its deletion
    ferritin.reference_ranges.create!(unit: units(:mgdl), sex: :any, high: 300)
    AnalyteAlias.create!(profile: alice, analyte: ferritin, name: "Ferritina")

    # The calendar: a day deleted from a series, a series shared, a month
    # open, and a day of each kind that differs from its series.
    events(:water_the_plants).event_exclusions.create!(date: events(:water_the_plants).starts_on + 7)
    EventShare.create!(event: events(:groceries), profile: bob)
    CalendarWatch.create!(profile: alice, year_month: "2026-10", subscription: "watch-1", seen_at: Time.current)
    occurrences(:groceries_due).write_details!(priority: :high)
    occurrences(:endocrinologist_due).write_details!(counterpart: "Dr. Rossi")
    occurrences(:bloodwork_due).override_details.save!
    meal_on(alice, Date.current, title: "Lunch").write_details!(meal_type: :lunch)

    # A dose drawn from a supply bought for a therapy, what that purchase
    # cost, a meal cooked from the pantry, groceries bought off a list.
    purchase = supply_purchase!(profile: alice, name: "Cobalamin vial", quantity: 5, collection: collections(:b12))
    expense!(profile: alice, date: Date.current, cents: 1200, about: purchase)
    dose = medication!(profile: alice, date: Date.current)
    dose.event.details.supply_uses.create!(supply: purchase.supply, quantity: 1)
    dose.complete!
    # The honey was taken out of the recipe after the meal, so only the meal names it.
    pantry_ingredient(alice, "Buckwheat", quantity: 1)
    pantry_ingredient(alice, "Honey", quantity: 1)
    pancakes = recipe_with(alice, "Pancakes", [ "Buckwheat", 100, "g" ], [ "Honey", 20, "g" ])
    meal_on(alice, Date.current, recipes: [ pancakes ]).complete!
    pancakes.recipe_ingredients.joins(:ingredient).where(ingredients: { name: "Honey" }).destroy_all
    expense!(profile: alice, date: Date.current, cents: 300, about: ingredient_purchase!(profile: alice))
    ingredient_purchase!(profile: alice, name: "Rice") # in no recipe and on no list
    supply_purchase!(profile: alice, name: "Plasters") # bought, in no plan
    grocery_lists(:weekly_shop).grocery_list_items.create!(ingredient: pantry_ingredient(alice, "Sugar", quantity: 0), quantity: 1).check!

    # What the admin pressed on the delivery console.
    Delivery::Request.create!(profile: alice, action: :deploy, destination: "staging")
  end
end
