# frozen_string_literal: true

require "test_helper"

class Assistant::ControllersTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
    @chat = assistant_chat(@alice)
  end

  test "the assistant opens the latest conversation" do
    get assistant_path
    assert_redirected_to assistant_chat_path(@chat)

    get assistant_chat_path(@chat)
    assert_response :success
    assert_select "#assistant-thread[role=log]", 1, "a screen reader reads what is added to it"
    assert_select "form#assistant-composer textarea[name=content]"
    assert_select "turbo-cable-stream-source"
  end

  test "with a cloud provider the composer says what leaves the server; with Ollama it says nothing" do
    get assistant_chat_path(@chat)
    assert_select ".assistant-composer__allowance--cloud", count: 0

    swapping(Assistant, :provider, -> { :anthropic }) { get assistant_chat_path(@chat) }
    assert_select ".assistant-composer__allowance--cloud", text: /sent to Anthropic/
  end

  test "someone else's conversation isn't there, as if it never was" do
    theirs = assistant_chat(profiles(:bob))
    get assistant_chat_path(@chat) # signed in for the requests after (a 404 writes no session cookie)

    get assistant_chat_path(theirs)
    assert_response :not_found
    post assistant_chat_messages_path(theirs), params: { content: "hi" }, as: :turbo_stream
    assert_response :not_found
    assert_empty theirs.assistant_messages.reload
  end

  test "sending a message queues the reply, and a second one waits its turn" do
    freeze_time { post assistant_chat_messages_path(@chat), params: { content: "I bought needles", time_zone: "Europe/Rome" }, as: :turbo_stream }
    claimed_at = @chat.reload.replying_since
    assert_enqueued_with(job: Assistant::ReplyJob, args: [ @chat, claimed_at ])
    assert_enqueued_with(job: Assistant::ReplyTimeoutJob, args: [ @chat, claimed_at ], at: claimed_at + Assistant::Chat::REPLY_TIMEOUT)
    assert_response :accepted
    assert_equal "I bought needles", @chat.reload.title
    assert_equal "Europe/Rome", @chat.time_zone
    assert_predicate @chat, :replying?

    post assistant_chat_messages_path(@chat), params: { content: "and syringes" }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_includes response.body, "still answering"
    assert_select "template form#assistant-composer .assistant-composer__btn--stop", 1, "the reply going on can still be stopped"
    assert_select "template form#assistant-composer a.assistant-composer__btn--stop[href=?][data-turbo-method=delete]", assistant_chat_reply_path(@chat)

    delete assistant_chat_reply_path(@chat), as: :turbo_stream
    assert_response :no_content
    assert_predicate @chat.reload, :cancelled?, "the reply stops at its next step"
  end

  test "a script sending too fast is told so in the thread, as a rate limit" do
    counting_rate_limits do
      20.times { post assistant_chat_messages_path(@chat), params: { content: "hi" }, as: :turbo_stream }
      assert_response :unprocessable_content, "the first is answering, so the rest wait their turn"

      post assistant_chat_messages_path(@chat), params: { content: "hi" }, as: :turbo_stream
      assert_response :too_many_requests
      assert_includes response.body, I18n.t("rate_limit.exceeded")
    end
  end

  test "an empty or oversized message is refused, saying why" do
    post assistant_chat_messages_path(@chat), params: { content: "  " }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_includes response.body, "Write a message or add a photo."

    post assistant_chat_messages_path(@chat), params: { content: "x" * 4001 }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_includes response.body, "up to 4000 characters"

    pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF"), "application/pdf", original_filename: "report.pdf")
    post assistant_chat_messages_path(@chat), params: { image: pdf }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_includes response.body, "JPEG, PNG, WebP or HEIC"
    assert_not @chat.reload.replying?
  end

  test "attaching a photo with no caption queues OCR instead of the reply, with a default caption" do
    image = fixture_file_upload("lab_report_sample.png", "image/png")

    assert_enqueued_with(job: Assistant::LabReportOcrJob) do
      post assistant_chat_messages_path(@chat), params: { content: "  ", image: image, time_zone: "Europe/Rome" }, as: :turbo_stream
    end
    assert_no_enqueued_jobs(only: Assistant::ReplyJob)
    assert_response :accepted

    message = @chat.reload.assistant_messages.where(role: "user").order(:id).last
    assert_equal I18n.t("assistant.defaults.lab_photo_caption"), message.content
    assert_predicate message.attachments, :attached?
  end

  test "several photos go on one message, up to the limit" do
    images = Array.new(3) { fixture_file_upload("lab_report_sample.png", "image/png") }

    assert_enqueued_with(job: Assistant::LabReportOcrJob) do
      post assistant_chat_messages_path(@chat), params: { images: images }, as: :turbo_stream
    end
    assert_equal 3, @chat.reload.assistant_messages.where(role: "user").order(:id).last.attachments.count

    @chat.release_reply!
    too_many = Array.new(Assistant::Message::MAX_IMAGES + 1) { fixture_file_upload("lab_report_sample.png", "image/png") }
    post assistant_chat_messages_path(@chat), params: { images: too_many }, as: :turbo_stream
    assert_response :unprocessable_content
  end

  test "an unsupported attachment type is rejected" do
    text_file = fixture_file_upload("lab_report_sample.png", "text/plain")

    post assistant_chat_messages_path(@chat), params: { image: text_file }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_not @chat.reload.replying?
  end

  test "neither content nor an image is rejected" do
    post assistant_chat_messages_path(@chat), params: {}, as: :turbo_stream
    assert_response :unprocessable_content
  end

  test "the debug trace shows admins every tool call, and nobody else" do
    run_tool(:search_records, @chat, type: "appointment", query: "Moretti")
    @chat.assistant_messages.create!(role: "user", content: "Any Moretti visits?")

    get assistant_chat_path(@chat, debug: 1)
    assert_select ".assistant-debug", 0, "a regular profile gets no trace"
    assert_select "a[aria-label=?]", I18n.t("assistant.debug.show"), 0

    @alice.update!(role: :admin)
    get assistant_chat_path(@chat, debug: 1)
    assert_select ".assistant-debug"
    assert_select ".assistant-debug__code", minimum: 1
    assert_select "a.assistant-debug__action[href=?]", new_assistant_evals_scenario_path(from_chat: @chat.id)
  end

  test "in development the trace is open to anyone, but only the admin may keep the chat as an eval" do
    @chat.assistant_messages.create!(role: "user", content: "Any Moretti visits?")

    swapping(Rails.env, :development?, -> { true }) { get assistant_chat_path(@chat, debug: 1) }

    assert_select ".assistant-debug"
    assert_select "a.assistant-debug__action", 0
  end

  def propose(_intents, operations, **options)
    submit_changes(@chat, operations, **options)
  end

  test "Apply on the card deletes; only the owner can press it, once" do
    first = appointment!(profile: @alice, date: Date.new(2026, 9, 25))
    second = appointment!(profile: @alice, date: Date.new(2026, 10, 2))
    set_id = propose([ "delete all appointments" ], [ { intent: 0, op: "delete", type: "appointment", fields: { all: true } } ])[:data][:change_set_id]

    sign_in profiles(:bob)
    post assistant_change_set_application_path(set_id), as: :turbo_stream
    assert Occurrence.exists?(first.id), "another profile can't apply it"

    sign_in @alice
    post assistant_change_set_application_path(set_id), as: :turbo_stream
    assert_response :success
    assert_not Occurrence.exists?(first.id)
    assert_not Occurrence.exists?(second.id)
    assert_not Appointment.exists?(first.event_id), "a one-off goes with its day"
    note = @chat.assistant_messages.order(:id).last
    assert_equal [ "user", true ], [ note.role, note.hidden ], "the model is told in the conversation; the thread doesn't show it"
    assert_not_includes @chat.visible_messages, note

    post assistant_change_set_application_path(set_id), as: :turbo_stream
    assert_response :forbidden, "answered once"
  end

  test "an Apply that fails says so on the card; a save that failed after its checks passed is also reported" do
    appointment!(profile: @alice, date: Date.new(2026, 9, 25))
    set_id = propose([ "delete all appointments" ], [ { intent: 0, op: "delete", type: "appointment", fields: { all: true } } ])[:data][:change_set_id]
    refused = ActiveRecord::RecordNotDestroyed.new("Failed to destroy Appointment with id=1")

    report = assert_error_reported(ActiveRecord::RecordNotDestroyed) do
      swapping(Assistant::ChangeSets::Applier, :call, ->(*, **) { raise refused }) { post assistant_change_set_application_path(set_id), as: :turbo_stream }
    end
    assert_equal set_id, report.context[:change_set_id]
    assert_toast I18n.t("assistant.change_sets.notices.failed")

    assert_no_error_reported do
      swapping(Assistant::ChangeSets::Applier, :call, ->(*, **) { raise Assistant::ChangeSets::Applier::NotReady }) do
        post assistant_change_set_application_path(set_id), as: :turbo_stream
      end
    end
    assert_toast I18n.t("assistant.change_sets.notices.failed")
  end

  test "Undo reverts a saved change; Cancel drops one in progress" do
    saved = propose([ "task" ], [ { intent: 0, op: "create", type: "task", fields: { title: "Call mum", date: "2026-09-30" } } ])
    assert_equal "saved", saved[:data][:status]

    delete assistant_change_set_application_path(saved[:data][:change_set_id]), as: :turbo_stream
    assert_response :success
    assert_not Task.exists?(title: "Call mum")

    pending = propose([ "book" ], [ { intent: 0, op: "create", type: "appointment", fields: { provider: "Rossi", date: "2026-09-30" } } ])
    delete assistant_change_set_path(pending[:data][:change_set_id]), as: :turbo_stream
    assert_predicate Assistant::ChangeSet.find(pending[:data][:change_set_id]), :cancelled?
  end

  test "a change someone else will see waits on its card, which says who" do
    propose([ "pay" ], [ { intent: 0, op: "create", type: "transaction",
                           fields: { title: "Rent share", amount: 50, kind: "income", category: "housing", payment_method: "cash",
                                     counterparty_profile_id: profiles(:bob).id, date: "2026-09-30" } } ])

    get assistant_chat_path(@chat)
    assert_select ".assistant-change-set--awaiting_confirmation .assistant-change-set__note", text: "Bob will see this."
    assert_select ".assistant-change-set__actions button", text: I18n.t("assistant.change_sets.buttons.apply")
  end

  test "a turn that ended without an answer says why where the answer would be, whenever the page is drawn" do
    travel_to 2.minutes.ago do
      @chat.assistant_messages.create!(role: "user", content: "Book the dentist")
      @chat.reply_failures.create!(reason: :unreachable)
    end
    @chat.assistant_messages.create!(role: "user", content: "Try again")

    get assistant_chat_path(@chat)

    assert_select ".assistant-notice--error", text: I18n.t("assistant.errors.unreachable")
    thread = css_select("##{Views::Assistant::Chats::Show::THREAD_ID} > *").map { _1["class"].split.first }
    assert_equal %w[assistant-message assistant-notice assistant-message], thread, "between the question it answers and the next one"
  end

  test "the chat shows change sets as cards" do
    propose([ "task" ], [ { intent: 0, op: "create", type: "task", fields: { title: "Call mum", date: "2026-09-30" } } ])

    get assistant_chat_path(@chat)
    assert_select ".assistant-change-set--applied", 1
    assert_select ".assistant-change-set form[action=?] input[name=_method][value=delete]", assistant_change_set_application_path(@chat.change_sets.last)
  end

  test "each saved row has its own edit button; the footer only holds Undo" do
    propose([ "task" ], [ { intent: 0, op: "create", type: "task", fields: { title: "Call mum", date: "2026-09-30" } } ])
    day = Task.find_by!(title: "Call mum").occurrences.sole

    get assistant_chat_path(@chat)
    assert_select ".assistant-change-set--applied .assistant-change-set__op a.item-action[href=?][data-turbo-stream][aria-label=?]",
                  edit_event_day_path(day.event, day.date), I18n.t("assistant.change_sets.buttons.edit_thing", thing: I18n.t("assistant.types.task"))
    assert_select ".assistant-change-set__actions a", 0
  end

  test "a purchase row is one edit button (its payment is in the purchase's form), and shows the price" do
    propose([ "buy" ], [ { intent: 0, op: "create", type: "supply_purchase",
                           fields: { supply: "Needles", quantity: 100, amount: 20, payment_method: "card", therapy: "Physio" } } ])
    purchase = SupplyPurchase.where(profile: @alice).last

    get assistant_chat_path(@chat)
    assert_select ".assistant-change-set__op", text: /Needles × 100 · €20[.,]00/
    assert_select ".assistant-change-set__op a.item-action", 1
    assert_select ".assistant-change-set__op a.item-action[href=?]", edit_supply_purchase_path(purchase)
  end

  test "a therapy added in the chat opens its own edit modal" do
    propose([ "therapy" ], [ { intent: 0, op: "create", type: "collection", fields: { name: "Physio" } } ])

    get assistant_chat_path(@chat)
    assert_select ".assistant-change-set__op a.item-action[href=?]", edit_collection_path(Collection.find_by!(profile: @alice, name: "Physio"))
  end

  test "a saved set that updated a record offers Review for it, once, and several get named" do
    appointment = appointment!(profile: @alice, date: Date.new(2026, 9, 25))
    propose([ "move" ], [ { intent: 0, op: "update", type: "appointment", ref: appointment.id.to_s, fields: { location: "Via Roma" } } ])

    get assistant_chat_path(@chat)
    assert_select "a.item-action[href=?]", edit_event_day_path(appointment.event, appointment.date), count: 1

    propose([ "two" ], [ { intent: 0, op: "create", type: "task", fields: { title: "Call mum", date: "2026-09-30" } },
                         { intent: 0, op: "create", type: "task", fields: { title: "Buy milk", date: "2026-09-30" } } ])
    get assistant_chat_path(@chat)
    assert_select "a.item-action[aria-label=?]", I18n.t("assistant.change_sets.buttons.edit_thing", thing: I18n.t("assistant.types.task")), count: 2
  end

  test "a draft still in progress opens its create modal, filled in" do
    pending = propose([ "book" ], [ { intent: 0, op: "create", type: "appointment", fields: { provider: "Rossi", date: "2026-09-30" } } ])
    set = Assistant::ChangeSet.find(pending[:data][:change_set_id])
    assert_predicate set, :in_progress?

    get assistant_chat_path(@chat)
    assert_select ".assistant-change-set__op a.item-action[href=?]", review_assistant_change_set_path(set, draft: 0)

    get review_assistant_change_set_path(set, draft: 0), as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=update][target=modals] form[action=?]", appointments_path
    assert_includes response.body, "Rossi"
    assert_no_difference "Appointment.count" do
      get review_assistant_change_set_path(set, draft: 0), as: :turbo_stream
    end
  end

  test "a draft visit's fee shows in its review form" do
    pending = propose([ "book" ], [ { intent: 0, op: "create", type: "appointment", fields: { provider: "Rossi", date: "2026-09-30", amount: 80 } } ])
    set = Assistant::ChangeSet.find(pending[:data][:change_set_id])

    get review_assistant_change_set_path(set, draft: 0), as: :turbo_stream
    assert_response :success
    amount = css_select("input[name='transaction[amount]']").first
    assert amount, "the form has its cost section"
    assert_equal 80, amount["value"].to_d
  end

  test "reviewing a draft is the owner's, and a missing draft says so" do
    pending = propose([ "book" ], [ { intent: 0, op: "create", type: "appointment", fields: { provider: "Rossi", date: "2026-09-30" } } ])
    set_id = pending[:data][:change_set_id]

    get review_assistant_change_set_path(set_id, draft: 7), as: :turbo_stream
    assert_response :unprocessable_content
    assert_toast I18n.t("assistant.change_sets.notices.review_unavailable")

    sign_in profiles(:bob)
    get review_assistant_change_set_path(set_id, draft: 0), as: :turbo_stream
    assert_response :not_found
  end

  test "every reviewable kind of draft opens its create modal" do
    needles = supply_purchase!(profile: @alice, name: "Needles").supply
    drafts = {
      "task" => [ { title: "Call mum" }, tasks_path ],
      "transaction" => [ { title: "Rent", amount: 500 }, transactions_path ],
      "medication" => [ { name: "Aspirin" }, medications_path ],
      "lab_test_result" => [ { title: "Blood", values: [ { analyte: "Calcium", value: 9.5, unit: "mg/dL" } ] }, lab_test_results_path ],
      "supply_purchase" => [ { supply: "Needles", quantity: 2, amount: 10, payment_method: "card" }, supply_purchases_path(needles) ]
    }
    drafts.each do |type, (fields, path)|
      set = Assistant::ChangeSet.create!(chat: @chat, profile: @alice, status: :open,
                                         operations: [ { "op" => "create", "type" => type, "fields" => fields.merge(date: "2030-01-01").stringify_keys } ])
      assert_predicate Assistant::ChangeSets::Review.draft_positions(Assistant::ChangeSets::Compiler.call(set).operations), :any?, type

      get review_assistant_change_set_path(set, draft: 0), as: :turbo_stream
      assert_response :success, type
      assert_select "turbo-stream[target=modals] form[action=?]", path
    end
  end

  test "a purchase of a supply still to be created has no form to review until the set is applied" do
    set = Assistant::ChangeSet.create!(chat: @chat, profile: @alice, status: :open,
                                       operations: [ { "op" => "create", "type" => "supply_purchase",
                                                       "fields" => { "supply" => "Gauze", "quantity" => 2, "amount" => 4, "payment_method" => "cash", "date" => "2030-01-01" } } ])

    assert_equal [ nil ], Assistant::ChangeSets::Review.draft_positions(Assistant::ChangeSets::Compiler.call(set).operations)
    get review_assistant_change_set_path(set, draft: 0), as: :turbo_stream
    assert_response :unprocessable_content
    assert_toast I18n.t("assistant.change_sets.notices.review_unavailable")
  end

  test "starting a conversation reuses a blank one instead of piling up empty chats" do
    assert_no_difference -> { Assistant::Chat.count } do
      2.times do
        post assistant_chats_path
        assert_redirected_to assistant_chat_path(@chat)
      end
    end

    @chat.note_for_model!("hello") # any message makes it a real conversation
    assert_difference -> { Assistant::Chat.count }, 1 do
      post assistant_chats_path
    end
    assert_redirected_to assistant_chat_path(Assistant::Chat.order(:id).last)
  end

  test "a blank conversation of someone else is never reused" do
    assistant_chat(profiles(:bob))
    @chat.destroy!

    assert_difference -> { Assistant::Chat.where(profile: @alice).count }, 1 do
      post assistant_chats_path
    end
  end

  test "renaming a conversation" do
    get edit_assistant_chat_path(@chat), as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target=modals] form[action=?]", assistant_chat_path(@chat)

    patch assistant_chat_path(@chat), params: { assistant_chat: { title: "  Pharmacy runs " } }, headers: submitted_from(assistant_chats_path)
    assert_redirected_to assistant_chats_path
    assert_equal "Pharmacy runs", @chat.reload.title
    follow_redirect!
    assert_toast "Chat renamed."

    patch assistant_chat_path(@chat), params: { assistant_chat: { title: "x" * 121 } }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_equal "Pharmacy runs", @chat.reload.title
  end

  test "someone else's conversation cannot be renamed or deleted" do
    theirs = assistant_chat(profiles(:bob))

    patch assistant_chat_path(theirs), params: { assistant_chat: { title: "Mine now" } }
    assert_nil theirs.reload.title

    assert_no_difference -> { Assistant::Chat.count } do
      delete assistant_chat_path(theirs)
    end
  end

  test "the list offers rename and delete for each conversation" do
    get assistant_chats_path
    assert_response :success
    assert_select "a.item-action[href=?][data-turbo-stream]", edit_assistant_chat_path(@chat)
    assert_select "a.item-action--danger[href=?][data-turbo-method=delete]", assistant_chat_path(@chat)
  end

  test "deleting a conversation from its page goes to the list, from the list stays on it" do
    assert_difference -> { Assistant::Chat.count }, -1 do
      delete assistant_chat_path(@chat), headers: submitted_from(assistant_chat_path(@chat))
    end
    assert_redirected_to assistant_chats_path
    follow_redirect!
    assert_toast "Chat deleted."

    other = assistant_chat(@alice)
    searched = assistant_chats_path(q: "pharmacy")
    delete assistant_chat_path(other), headers: submitted_from(searched)
    assert_redirected_to searched
  end
end
