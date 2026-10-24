# frozen_string_literal: true

require "test_helper"

# Deleting a record that other rows point at is refused where the person
# stands, or takes along what hangs off it, or lets go of it: never a 500,
# and never a reference left naming a row that is gone. Generated from the
# routes and the schema. Every route that deletes a record says which kind
# and who may delete one; every reference to that kind (a foreign key, or a
# polymorphic association the kind declares) is then tried on a row of the
# example household that something names, as its owner, and rolled back.
# A new route, table or reference is tried the day it exists, or fails here
# until EveryTable gives it a row to try.
class DeletingWhatIsReferencedTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess::FixtureFile

  # What a route deletes, who may delete one, and the `scope` it is sent
  # with (a day's route deletes the whole series with "series").
  Deletion = Data.define(:controller, :model, :by, :scope) do
    def initialize(controller:, model:, by: :profile, scope: nil) = super
  end

  DELETIONS = [
    Deletion.new(controller: "links", model: Link, by: :requester),
    Deletion.new(controller: "link_approvals", model: LinkApproval, by: :owner),
    Deletion.new(controller: "days", model: Occurrence, by: ->(day) { day.event.profile }),
    Deletion.new(controller: "days", model: Event, scope: "series"),
    Deletion.new(controller: "collections", model: Collection),
    Deletion.new(controller: "analytes", model: Analyte),
    Deletion.new(controller: "reference_ranges", model: ReferenceRange, by: ->(range) { range.analyte.profile }),
    Deletion.new(controller: "supplies", model: Supply),
    Deletion.new(controller: "supply_purchases", model: SupplyPurchase),
    Deletion.new(controller: "ingredients", model: Ingredient),
    Deletion.new(controller: "ingredient_purchases", model: IngredientPurchase),
    Deletion.new(controller: "recipes", model: Recipe),
    Deletion.new(controller: "grocery_lists", model: GroceryList),
    Deletion.new(controller: "grocery_list_items", model: GroceryListItem, by: ->(item) { item.grocery_list.profile }),
    Deletion.new(controller: "books", model: Book),
    Deletion.new(controller: "uploads", model: Upload),
    Deletion.new(controller: "upload_links", model: UploadLink, by: ->(link) { link.upload.profile }),
    Deletion.new(controller: "messages", model: Message, by: :sender),
    Deletion.new(controller: "assistant/chats", model: Assistant::Chat),
    Deletion.new(controller: "assistant/change_sets", model: Assistant::ChangeSet)
  ].freeze

  # Routes that delete nothing another row points at, each with why.
  NOTHING_REFERENCED = {
    "day_completions" => "takes a day's completion back; the day stays",
    "grocery_list_completions" => "reopens a list; the list stays",
    "grocery_list_item_checks" => "unticks an item; the item stays",
    "shares" => "stops sharing something; nothing points at a share",
    "message_reactions" => "takes a reaction back; nothing points at one",
    "push_subscriptions" => "forgets a device; nothing points at its subscription",
    "household_invitations" => "takes back an invitation nobody answered, which owns nothing and can't be shared with",
    "household_members" => "removes a person through Profiles::Destroy, which Profiles::DestroyTest holds to the schema",
    "assistant/chat_replies" => "stops a reply; the chat stays",
    "assistant/change_set_applications" => "undoes a change set; the set stays",
    "assistant/settings" => "clears a provider's key, not a record",
    "profiles/sessions" => "signs out"
  }.freeze

  # A reference allowed to name a row that is gone, with why.
  OUTLIVING = {
    "notifications.subject_id" => "a notification keeps its subject's title, so it still reads right once the subject is gone"
  }.freeze

  # A reference to a kind: a foreign key, or a polymorphic association
  # whose `type` column holds the kind's name.
  Pointer = Data.define(:table, :column, :type) do
    def to_s = "#{table}.#{column}"
  end

  test "every route that deletes says what it deletes" do
    unsaid = delete_routes.map { _1.defaults[:controller] }.uniq - DELETIONS.map(&:controller) - NOTHING_REFERENCED.keys

    assert_empty unsaid, "say what each of these deletes (DELETIONS), or why nothing points at it (NOTHING_REFERENCED)"
  end

  test "deleting what something points at is refused or done cleanly, never a 500" do
    give_the_example_household_a_row_everywhere
    rows = OwnedRows.new
    household = rows.of(households(:example))

    failures = DELETIONS.flat_map do |deletion|
      ours = household.fetch(deletion.model.table_name, Set.new)
      naming = pointers_to(deletion.model).to_h { |pointer| [ pointer, named_by(pointer).select { ours.include?(_1) } ] }
      naming.filter_map do |pointer, ids|
        next "#{pointer} names no #{deletion.model.name} of the example household: give it one in EveryTable" if ids.empty?

        # The row fewest other references name, so that a refusal is this one's.
        id = ids.min_by { |candidate| naming.count { |other, named| other != pointer && named.include?(candidate) } }
        try(deletion, deletion.model.find(id), pointer, rows)
      end
    end

    assert_empty failures
  end

  private

  def delete_routes
    Rails.application.routes.routes.select do |route|
      route.verb == "DELETE" && route.defaults[:controller] && !route.defaults[:controller].start_with?("admin/", "assistant/evals/", "devise/")
    end
  end

  # Deletes `record` as whoever may, inside a savepoint rolled back after;
  # what went wrong, if anything.
  def try(deletion, record, pointer, rows)
    named = "#{deletion.controller}: a #{deletion.model.name} named by #{pointer}"
    failure = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      failure = attempt(deletion, record, rows)&.then { "#{named} #{_1}" }
      raise ActiveRecord::Rollback
    end
    failure
  end

  def attempt(deletion, record, rows)
    sign_in deletion.by.to_proc.call(record)
    process(:delete, path_to(deletion, record), as: :turbo_stream)
    dangling = rows.dangling(outliving: OUTLIVING.keys)

    if !response.status.in?([ 200, 204, 302, 303, 422 ]) then "answered #{response.status}"
    elsif dangling.any? then "left #{dangling.to_sentence}"
    end
  rescue StandardError => e
    "raised #{e.class}: #{e.message.lines.first.strip}"
  end

  # The day's route is the series' too, reached through any of its days.
  def path_to(deletion, record)
    route = delete_routes.find { _1.defaults[:controller] == deletion.controller }
    day = record.is_a?(Event) ? (record.occurrences.first || record.occurrence_on(record.starts_on)) : record
    parts = (route.required_parts - [ :format ]).to_h { |part| [ part, part == :date ? day.date.iso8601 : day.public_send(part) ] }
    query = { scope: deletion.scope, time: (day.time_string if day.is_a?(Occurrence)) }.compact
    [ route.format(parts), query.to_query.presence ].compact.join("?")
  end

  def pointers_to(model)
    connection = ActiveRecord::Base.connection
    # A key of several columns (a day's details, to the day and its series)
    # starts with the one that holds the id.
    keys = connection.tables.flat_map do |table|
      connection.foreign_keys(table).select { _1.to_table == model.table_name }
        .map { Pointer.new(table:, column: Array(_1.column).first, type: nil) }
    end
    polymorphic = model.reflect_on_all_associations.select { _1.options[:as] }.map do |association|
      Pointer.new(table: association.klass.table_name, column: association.foreign_key.to_s, type: model.polymorphic_name)
    end
    keys + polymorphic
  end

  # The ids of the rows `pointer` names.
  def named_by(pointer)
    connection = ActiveRecord::Base.connection
    of_type = " AND #{pointer.column.delete_suffix("_id")}_type = #{connection.quote(pointer.type)}" if pointer.type
    connection.select_values("SELECT DISTINCT #{pointer.column} FROM #{pointer.table} WHERE #{pointer.column} IS NOT NULL#{of_type}")
  end
end
