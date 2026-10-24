# frozen_string_literal: true

require "test_helper"

# Removing one person while the housemates stay: what is theirs goes, read
# from the schema (OwnedRows), and what the housemates kept stays, unlinked
# from what went. The database and the files keep in step: what lives
# outside the database goes only once the removal has committed. (A whole
# household going is Households::DestroyTest's.)
class Profiles::DestroyTest < ActiveSupport::TestCase
  include ActionDispatch::TestProcess::FixtureFile

  # References a housemate's row can't make to something of hers, each with
  # why. A key of several columns can't either: the others make its row
  # agree with the row it names, as a day's details agree with the day's
  # series.
  ONLY_FROM_HER_OWN = {
    "link_approvals.event_id" => "a request is about the records of someone on its link, and goes with the link",
    "link_approvals.occurrence_id" => "a request is about the records of someone on its link, and goes with the link",
    "ingredient_purchases.grocery_list_item_id" => "what is bought off a list is of its owner's pantry",
    "upload_activities.upload_link_id" => "only a file's owner makes links to it, so their uses are on her file's trail",
    "ruby_llm_tool_calls.result_id" => "a tool call and its result are in one conversation",
    "ruby_llm_usages.message_id" => "a reply and what it cost are in one conversation"
  }.freeze

  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
  end

  test "a person goes with what is theirs, and the housemates keep theirs, unlinked from it" do
    give_the_example_household_a_row_everywhere
    kept = keep_housemates_things_about_alice
    rows = OwnedRows.new
    household = rows.of(households(:example))
    hers = rows.of(@alice)
    went = went_with_her

    Profiles::Destroy.call(@alice)

    going = hers.merge(went) { |_, mine, more| mine | more }
    still_there = going.filter_map { |table, ids| "#{table}: #{ids_left(table, ids).size}" if ids_left(table, ids).any? }
    assert_empty still_there, "what goes with her is still there"
    gone = household.filter_map do |table, ids|
      others = ids - hers.fetch(table, Set.new) - went.fetch(table, Set.new)
      "#{table}: #{(others - ids_left(table, others)).size}" if ids_left(table, others) != others
    end
    assert_empty gone, "what the housemates kept is gone"
    assert_empty rows.dangling

    assert_nil kept[:visit].reload.collection_id, "a visit filed in her therapy is in none"
    assert_nil kept[:purchase].reload.collection_id, "a purchase made for her therapy is for none"
    assert_nil kept[:cost].reload.details.about, "a cost about her purchase is about nothing"
    assert_equal [ nil ], SupplyConsumption.where(occurrence: kept[:dose]).pluck(:supply_purchase_id),
                 "a dose drawn from her purchase keeps what it drew"
    assert_nil kept[:transfer].reload.details.counterparty_profile, "a payment to her has no other side"
    assert_nil @bob.reload.invited_by, "who she invited was invited by nobody"
    assert_nil households(:example).reload.owner, "her household has no owner until someone is named"
    assert_nil Conversation.household_conversation(households(:example)).participant_for(@bob).last_read_message,
               "a housemate who had read up to her picture has read none of what is left"
    assert_nil Assistant::Setting.sole.updated_by
    assert_nil Platform::Setting.sole.updated_by
    kept[:edited].each do |record|
      assert_nil record.reload.updated_by, "#{record.class.name} of his that she saved last was saved by nobody"
    end
  end

  test "every reference a housemate's row may make to something of hers is tried above" do
    give_the_example_household_a_row_everywhere
    keep_housemates_things_about_alice
    rows = OwnedRows.new
    hers = rows.of(@alice)
    people_own = rows.ownable(by: "profiles")

    untried = rows.pointing.filter_map do |ref|
      next if ONLY_FROM_HER_OWN.key?("#{ref.table}.#{ref.column}") || agreeing.include?([ ref.table, ref.column ])
      next unless ref.polymorphic? || people_own.include?(ref.owner)

      "#{ref.table}.#{ref.column}" unless named_by_others?(ref, hers)
    end

    assert_empty untried, "give a housemate's row naming something of hers in keep_housemates_things_about_alice, " \
                          "or say why none can (ONLY_FROM_HER_OWN)"
  end

  test "a removal rolled back leaves every picture and file where it was" do
    blob, file = keep_pictures_and_files(@bob)

    ActiveRecord::Base.transaction(requires_new: true) do
      Profiles::Destroy.call(@bob)
      raise ActiveRecord::Rollback
    end

    assert_no_enqueued_jobs only: ActiveStorage::PurgeJob
    assert ActiveStorage::Blob.exists?(blob.id)
    assert_path_exists file.path
    assert Profile.exists?(@bob.id)
  end

  test "a removal that commits takes the pictures and the files with it" do
    blob, file = keep_pictures_and_files(@bob)

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { Profiles::Destroy.call(@bob) }

    assert_not ActiveStorage::Blob.exists?(blob.id)
    refute_path_exists file.path
    assert_not Profile.exists?(@bob.id)
  end

  private

  # What Bob keeps that names something of Alice's: a visit and a purchase
  # in the therapy she shares with him (the B12 fixture), a cost about her
  # purchase, a restock of her supply, a dose of his drawn from her restock
  # of his supply once his own had run out, a payment to her, and his own
  # invitation. What of hers is on his days goes with her: a dose drawn from
  # her supply, her recipe in his meal, her share of his series and her
  # reminder on it. Their direct conversation goes whole, and so does her
  # download of his file from its trail. What she last saved of the app's
  # settings and of his things they edit together stays, saved by nobody.
  def keep_housemates_things_about_alice
    therapy = collections(:b12)
    visit = series!("Appointment", profile: @bob, starts_on: Date.current, title: "Check-up", kind: :medical, collection: therapy)
    purchase = supply_purchase!(profile: @bob, name: "Plasters", collection: therapy)
    hers = supply_purchase!(profile: @alice, name: "B12 ampoule", collection: therapy)
    restock!(hers.supply, by: @bob, collection: therapy)
    cost = expense!(profile: @bob, date: Date.current, cents: 900, about: hers).event

    collections(:fibromyalgia).collection_shares.create!(profile: @alice)
    needles = supply_purchase!(profile: @bob, name: "Needles", remaining: 0, collection: collections(:fibromyalgia)).supply
    restock!(needles, by: @alice, collection: therapy)
    dose = medication!(profile: @bob, date: Date.current)
    dose.event.details.supply_uses.create!(supply: needles, quantity: 1)
    dose.complete!

    vitamin = medication!(profile: @bob, date: Date.current, name: "Vitamin D")
    vitamin.event.details.supply_uses.create!(supply: hers.supply, quantity: 1)
    vitamin.complete!
    meal_on(@bob, Date.current, recipes: [ recipes(:roast_chicken) ])
    recycling = task!(profile: @bob, date: Date.current, title: "Recycling").event
    recycling.event_shares.create!(profile: @alice)
    recycling.event_reminders.create!(profile: @alice, offset_minutes: 30).deliveries.create!(date: Date.current)
    push_subscription_for(@alice)

    send_message(Conversation.direct_between(@alice, @bob), @bob, "see you")
    transfer = transfer!(payer: @bob, counterparty: @alice, date: Date.current, cents: 2500).event
    @bob.update!(invited_by: @alice)
    file = keep_file(@bob, name: "lease.txt")
    file.upload_shares.create!(profile: @alice)
    UploadActivity.record(file, :downloaded, actor: @alice)
    Assistant::Setting.create!(provider: "ollama", model: "qwen3", ollama_url: "http://ollama.local:11434", updated_by: @alice)
    Platform::Setting.create!(updated_by: @alice)
    list = GroceryList.create!(profile: @bob, name: "Weekly shop")
    milk = list.grocery_list_items.create!(ingredient: pantry_ingredient(@bob, "Milk", quantity: 0, unit: "l"), quantity: 1)
    edited = [ visit, dose, purchase, collections(:fibromyalgia), recipes(:pancakes), list, milk,
               Conversation.household_conversation(households(:example)) ]
    edited.each { _1.update_columns(updated_by_id: @alice.id) }

    { visit: visit, purchase: purchase, cost: cost, dose: dose, transfer: transfer, edited: edited }
  end

  # What goes with her though it isn't hers in the schema: her direct
  # conversations, whole, since nobody is left to talk in them, and what she
  # did under a housemate's bell.
  def went_with_her
    direct = Conversation.direct.where(id: ConversationParticipant.where(profile_id: @alice.id).select(:conversation_id))
    {
      "conversations" => Set.new(direct.ids),
      "conversation_participants" => Set.new(ConversationParticipant.where(conversation: direct).ids),
      "messages" => Set.new(Message.where(conversation: direct).ids),
      "notifications" => Set.new(Notification.where(actor: @alice).ids),
      "upload_activities" => Set.new(UploadActivity.where(profile: @alice).ids)
    }
  end

  # Whether a row that isn't hers names one of hers through `ref`.
  def named_by_others?(ref, hers)
    type = ref.polymorphic? ? ref.type_column : "NULL"
    ActiveRecord::Base.connection.select_rows("SELECT id, #{type}, #{ref.column} FROM #{ref.table} WHERE #{ref.column} IS NOT NULL")
      .any? do |id, named_type, named|
        named_table = ref.polymorphic? ? named_type&.constantize&.table_name : ref.owner
        hers.fetch(named_table, Set.new).include?(named) && !hers.fetch(ref.table, Set.new).include?(id)
      end
  end

  # The first column of each key of several, by table.
  def agreeing
    connection = ActiveRecord::Base.connection
    connection.tables.flat_map do |table|
      connection.foreign_keys(table).select { _1.column.is_a?(Array) }.map { [ table, _1.column.first ] }
    end
  end

  def restock!(supply, by:, collection:)
    SupplyPurchase.create!(supply: supply, profile: by, collection: collection,
                           quantity_purchased: 5, quantity_remaining: 5, purchased_on: Date.current)
  end

  def ids_left(table, ids)
    return Set.new if ids.empty?

    Set.new(ActiveRecord::Base.connection.select_values("SELECT id FROM #{table} WHERE id IN (#{ids.to_a.join(", ")})"))
  end

  def keep_pictures_and_files(profile)
    message = send_message(Conversation.household_conversation(profile.household), profile, "the receipt", images: [ picture_upload ])
    [ message.images.sole.blob, keep_file(profile) ]
  end
end
