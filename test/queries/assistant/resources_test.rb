# frozen_string_literal: true

require "test_helper"

# The registry of what the assistant works with: how a type is found, and
# what a page of its records costs to summarize.
class Assistant::ResourcesTest < ActiveSupport::TestCase
  setup { @alice = profiles(:alice) }

  test "a type is found by its key, a word for it, or the record itself" do
    assert_equal "reference_range", Assistant::Resources.fetch("normal range").key
    assert_equal "meal", Assistant::Resources.lookup(:Dinners).key
    assert_nil Assistant::Resources.lookup("spaceship")
    assert_equal "task", Assistant::Resources.for_record(occurrences(:groceries_due)).key
    assert_equal "collection", Assistant::Resources.for_record(collections(:b12)).key

    error = assert_raises(ArgumentError) { Assistant::Resources.fetch("spaceship") }
    assert_match "Known: task, appointment", error.message
  end

  test "every kind of series has a resource, and the tools offer every resource" do
    Event.types.each { |kind| assert Assistant::Resources.lookup(kind.name.underscore), "#{kind} has no resource" }

    assert_equal Assistant::Resources.keys, Assistant::ChangeTool::TYPES
    offered = Assistant::SearchRecordsTool.declared_parameters[:type].description
    Assistant::Resources.keys.each { |key| assert_includes offered, key }
  end

  test "a kind says who sees one of its records: the owner, and whoever it reaches by sharing or a link" do
    bob = profiles(:bob)
    b12 = collections(:b12)
    purchase = SupplyPurchase.create!(supply: Supply.create!(profile: @alice, name: "Needles", category: :consumable, unit_label: "pieces"),
                                      profile: @alice, collection: b12, quantity_purchased: 10, quantity_remaining: 10, purchased_on: Date.new(2026, 9, 1))

    assert_equal [ @alice, bob ], Assistant::Resources.fetch("collection").readers(b12)
    assert_equal [ @alice, bob ], Assistant::Resources.fetch("supply_purchase").readers(purchase)
    assert_equal [ @alice, bob ], Assistant::Resources.fetch("supply").readers(purchase.supply)
    assert_equal [ @alice, bob ], Assistant::Resources.fetch("grocery_list").readers(grocery_lists(:weekly_shop))
    assert_equal [ @alice ], Assistant::Resources.fetch("reference_range").readers(reference_ranges(:glucose_any))
    assert_equal [ @alice ], Assistant::Resources.fetch("analyte").readers(analytes(:glucose))
    assert_equal occurrences(:groceries_due).event.audience, Assistant::Resources.fetch("task").readers(occurrences(:groceries_due))
    payment = Transaction.new(profile: @alice, starts_on: Date.new(2026, 9, 23))
    payment.details.counterparty_profile_id = bob.id
    assert_equal [ @alice, bob ], Assistant::Resources.fetch("transaction").readers(payment.first_occurrence), "not saved yet, with its counterparty"
  end

  test "a page of summaries reads what it needs once, not once per record" do
    gnocchi, polenta, soup = [ "Gnocchi", "Polenta", "Soup" ].map { |name| recipe_with(@alice, name, [ name.downcase, 100, "g" ]) }
    recipes = Assistant::Resources.fetch("recipe")

    one = count_queries { recipes.summarize_all([ gnocchi ], profile: @alice) }
    three = count_queries { recipes.summarize_all([ gnocchi, polenta, soup ], profile: @alice) }

    assert_equal one, three
    assert_equal [ "gnocchi: none in the pantry" ], recipes.summarize(gnocchi, profile: @alice)[:short_in_pantry]
  end

  test "a search from a date, or up to one, leaves the other end open" do
    supply = Supply.create!(profile: @alice, name: "Strips", unit_label: "strip")
    old, recent = [ Date.new(2024, 1, 10), Date.new(2026, 9, 10) ].map do |day|
      SupplyPurchase.create!(profile: @alice, supply: supply, quantity_purchased: 1, quantity_remaining: 1, purchased_on: day)
    end
    purchases = Assistant::Resources.fetch("supply_purchase")

    assert_equal [ recent.id ], ids_of(purchases.search(@alice, date_from: Date.new(2026, 1, 1)))
    assert_equal [ old.id ], ids_of(purchases.search(@alice, date_to: Date.new(2025, 1, 1)))
  end

  private

  def ids_of(summaries) = summaries.map { |summary| summary[:id] }

  def count_queries(&block)
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("SAVEPOINT", "RELEASE") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    queries
  end
end
