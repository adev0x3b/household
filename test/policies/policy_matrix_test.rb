# frozen_string_literal: true

require "test_helper"

# Who may do what with a record, for every kind a policy guards: read top
# to bottom, it is the app's authorization model. A record is Alice's; the
# people who ask are
#
#   owner      Alice herself
#   sharee     Bob, a housemate she shared it with (where the kind shares)
#   housemate  Carol, of the same household, it isn't shared with
#   outsider   Dave, of another household
#   admin   an admin of another household: runs the app, sees no one's things
#
# Each row lists what the owner and the sharee may do; everyone else may do
# none of it. A policy that drifts from this fails here, naming the kind,
# the person and the action. (What a whole page allows — index?, create? —
# is each controller's test; a day's link grants are the second table.)
class PolicyMatrixTest < ActiveSupport::TestCase
  PEOPLE = %i[owner sharee housemate outsider admin].freeze

  RECORDS = {
    "a recipe" => {
      record: -> { Recipe.create!(profile: @alice, name: "Soup") },
      share: ->(recipe) { RecipeShare.create!(recipe: recipe, profile: @bob) },
      owner: %i[show? update? destroy?], sharee: %i[show? update?]
    },
    "a book" => {
      record: -> { Book.create!(profile: @alice, title: "Dune", author: "Frank Herbert") },
      share: ->(book) { BookShare.create!(book: book, profile: @bob) },
      owner: %i[show? update? destroy? change_status?], sharee: %i[show?]
    },
    "a collection" => {
      record: -> { Collection.create!(profile: @alice, name: "B12", section: "healthcare") },
      share: ->(collection) { CollectionShare.create!(collection: collection, profile: @bob) },
      owner: %i[show? update? destroy?], sharee: %i[show? update?]
    },
    "a grocery list" => {
      record: -> { GroceryList.create!(profile: @alice, name: "Saturday") },
      share: ->(list) { GroceryListShare.create!(grocery_list: list, profile: @bob) },
      owner: %i[show? update? destroy? finish? reopen?], sharee: %i[show? update? finish? reopen?]
    },
    "an item on a grocery list" => {
      record: -> { GroceryList.create!(profile: @alice, name: "Saturday").grocery_list_items.create!(ingredient: pantry_ingredient(@alice, "Milk", quantity: 1)) },
      share: ->(item) { GroceryListShare.create!(grocery_list: item.grocery_list, profile: @bob) },
      owner: %i[create? update? destroy? check? uncheck?], sharee: %i[create? update? destroy? check? uncheck?]
    },
    "an ingredient" => {
      record: -> { pantry_ingredient(@alice, "Rice", quantity: 2) },
      owner: %i[show? update? destroy?]
    },
    "a grocery purchase" => {
      record: -> { ingredient_purchase!(profile: @alice) },
      owner: %i[create? edit? update? destroy?]
    },
    "an analyte" => {
      record: -> { Analyte.create!(profile: @alice, name: "Ferritin") },
      owner: %i[show? update? destroy?]
    },
    "a reference range" => {
      record: -> { ReferenceRange.create!(analyte: Analyte.create!(profile: @alice, name: "Ferritin"), unit: units(:mgdl), sex: :any, high: 300) },
      owner: %i[create? update? destroy?]
    },
    # Shared through a collection: what was bought for a therapy is seen by
    # whoever the therapy is shared with, and restocked by them.
    "a supply" => {
      record: -> { supply_purchase!(profile: @alice, name: "Needles", collection: @therapy).supply },
      share: ->(_supply) { CollectionShare.create!(collection: @therapy, profile: @bob) },
      owner: %i[show? create? update? destroy?], sharee: %i[show?]
    },
    "a supply purchase" => {
      record: -> { supply_purchase!(profile: @alice, name: "Needles", collection: @therapy) },
      share: ->(_purchase) { CollectionShare.create!(collection: @therapy, profile: @bob) },
      owner: %i[edit? update? destroy?], sharee: %i[edit? update?]
    },
    "a file" => {
      record: -> { keep_file(@alice) },
      share: ->(upload) { UploadShare.create!(upload: upload, profile: @bob) },
      owner: %i[show? download? update? destroy? link? chunk? progress?], sharee: %i[show? download?]
    },
    "a file's link" => {
      record: -> { mint_link(keep_file(@alice)).first },
      owner: %i[destroy?]
    },
    "a notification" => {
      record: -> { Notification.create!(profile: @alice, kind: :shared, subject: recipes(:roast_chicken), subject_title: "Soup") },
      owner: %i[show? read?]
    },
    "a device's push subscription" => {
      record: -> { push_subscription_for(@alice) },
      owner: %i[destroy?]
    }
  }.freeze

  setup do
    @alice, @bob, @carol, @dave = profiles(:alice), profiles(:bob), profiles(:carol), profiles(:outsider)
    @admin = Profile.create!(household: households(:elsewhere), username: "admin", email: "admin@example.com",
                             password: "a long enough password", role: :admin)
    @therapy = Collection.create!(profile: @alice, name: "B12", section: "healthcare")
  end

  RECORDS.each do |name, row|
    test "#{name}: who may do what" do
      record = instance_exec(&row[:record])
      instance_exec(record, &row[:share]) if row[:share]
      actions = (row[:owner] + row.fetch(:sharee, [])).uniq

      assert_matrix(record, actions, owner: row[:owner], sharee: row.fetch(:sharee, []))
    end
  end

  # A day on Alice's calendar (a task): her own, a housemate's it is shared
  # with — the series or its collection — and the link's grants, read on and
  # the rest asked by default (asking allows, and LinkApprovable holds the
  # change for her OK).
  DAY_ACTIONS = %i[show? edit? update? change_status? destroy?].freeze

  test "a day of a series: owner, sharee and the link's grants" do
    day = task!(profile: @alice, date: Date.new(2026, 10, 6))
    EventShare.create!(event: day.event, profile: @bob)

    assert_matrix(day, DAY_ACTIONS, owner: DAY_ACTIONS, sharee: DAY_ACTIONS - %i[destroy?])
  end

  test "a day of a series shared through its collection is the sharee's to change, not to delete" do
    day = task!(profile: @alice, date: Date.new(2026, 10, 6))
    day.event.update!(collection: @therapy)
    CollectionShare.create!(collection: @therapy, profile: @bob)

    assert_matrix(day, DAY_ACTIONS, owner: DAY_ACTIONS, sharee: DAY_ACTIONS - %i[destroy?])
  end

  test "a linked housemate does what the grant for that kind says: read on, the rest asked — allowed, then held for her OK" do
    day = task!(profile: @alice, date: Date.new(2026, 10, 6))
    link!(@alice, @bob)
    assert_matrix(day, DAY_ACTIONS, owner: DAY_ACTIONS, sharee: DAY_ACTIONS)
    assert_equal DAY_ACTIONS - %i[show?], held(day), "asked: each change waits for Alice (LinkApprovable)"

    grant(@alice, @bob, "Task", write: :on, delete: :on)
    assert_empty held(day), "on: done straight away"

    grant(@alice, @bob, "Task", read: :off)
    assert_matrix(day, DAY_ACTIONS, owner: DAY_ACTIONS, sharee: [], label: "read off turns the rest off")
  end

  test "a payment's other side reads it and nothing more, and doesn't read the rest of the series' kind" do
    day = transfer!(payer: @alice, counterparty: @bob, date: Date.new(2026, 10, 6), cents: 4000)

    assert_matrix(day, DAY_ACTIONS, owner: DAY_ACTIONS, sharee: %i[show?])
  end

  private

  # What Bob may do with the day only once Alice says yes.
  def held(day)
    Links::Permissions.reset!
    policy = Pundit.policy!(@bob, day)
    DAY_ACTIONS.select { policy.public_send(_1) && policy.needs_approval?(_1) }
  end

  # Every person against every action: allowed exactly where the row says.
  def assert_matrix(record, actions, owner:, sharee:, label: nil)
    Links::Permissions.reset!
    expected = { owner: owner, sharee: sharee }
    people = { owner: @alice, sharee: @bob, housemate: @carol, outsider: @dave, admin: @admin }
    wrong = PEOPLE.flat_map do |person|
      policy = Pundit.policy!(people.fetch(person), record)
      actions.filter_map do |action|
        allowed = policy.public_send(action)
        should = expected.fetch(person, []).include?(action)
        "#{person} #{allowed ? "may" : "may not"} #{action.to_s.delete_suffix("?")}" if allowed != should
      end
    end

    assert_empty wrong, [ record.class.name, label ].compact.join(": ")
  end
end
