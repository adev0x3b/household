# frozen_string_literal: true

require "test_helper"

# "Add tuna to the grocery list": the list in use is the one meant, whether
# the model reaches for update_record without naming it, or for
# add_grocery_list with a name the list already has or one that only says
# "grocery list". Several in use are asked about; a finished list is never
# picked; confirm starts another on purpose.
class Assistant::GroceryListsTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:carol) # no grocery lists of its own in the fixtures
    @chat = assistant_chat(@alice)
    @september = list!("Spesa di settembre", "Pane", status: :completed)
  end

  def list!(name, *items, status: :active)
    GroceryList.create!(profile: @alice, name: name, status: status).tap do |list|
      items.each { list.grocery_list_items.create!(ingredient_name: _1) }
    end
  end

  def items_on(list) = list.reload.grocery_list_items.map { _1.ingredient.name }.sort

  test "update_record with no ref puts the items on the one list in use, its type read from them" do
    spesa = list!("Lista spesa", "Latte")
    result = run_tool(:update_record, @chat, items: [ { ingredient: "Tonno" } ])

    assert_equal "saved", result.dig(:data, :status), result.inspect
    assert_equal %w[Latte Tonno], items_on(spesa)
    assert_equal %w[Pane], items_on(@september)
  end

  test "add_grocery_list with a list's name in another case, or a name that only says grocery list, adds to it" do
    spesa = list!("Lista spesa", "Latte")

    assert_equal "saved", run_tool(:add_grocery_list, @chat, name: "Lista Spesa", items: [ { ingredient: "Tonno" } ]).dig(:data, :status)
    assert_equal "saved", run_tool(:add_grocery_list, assistant_chat(@alice), name: "lista della spesa", items: [ { ingredient: "Dado" } ]).dig(:data, :status)
    assert_equal %w[Dado Latte Tonno], items_on(spesa)
    assert_equal 2, GroceryList.where(profile: @alice).count, "no second list"
  end

  test "with two lists in use, the grocery list is asked about by name; the one named then gets the item" do
    list!("Mercato", "Latte")
    esselunga = list!("Esselunga", "Caffè")

    asked = run_tool(:add_grocery_list, @chat, name: "Lista della spesa", items: [ { ingredient: "Tonno" } ])
    assert_equal "needs_input", asked.dig(:data, :status), asked.inspect
    assert_equal %w[Esselunga Mercato], asked.dig(:data, :changes, 0, :candidates).map { _1[:name] }.sort

    named_after_it = run_tool(:add_grocery_list, assistant_chat(@alice), name: "tonno", items: [ { ingredient: "Tonno" } ])
    assert_equal "needs_input", named_after_it.dig(:data, :status), "a list named after its one item is the model's name, not a new list"

    named = run_tool(:update_record, @chat, type: "grocery_list", ref: "esselunga", items: [ { ingredient: "Tonno" } ])
    assert_equal "saved", named.dig(:data, :status), named.inspect
    assert_equal %w[Caffè Tonno], items_on(esselunga)
  end

  test "a new list on purpose: another name, or confirm (a second list of the same name waits for the user's OK); a name alone that is in use says so" do
    list!("Lista spesa", "Latte")

    assert_equal "saved", run_tool(:add_grocery_list, @chat, name: "Compleanno", items: [ { ingredient: "Candeline" } ]).dig(:data, :status)
    assert_equal 3, GroceryList.where(profile: @alice).count
    again = run_tool(:add_grocery_list, assistant_chat(@alice), name: "Lista spesa", items: [ { ingredient: "Riso" } ], confirm: true)
    assert_equal "waiting_for_user", again.dig(:data, :status), "a possible duplicate: the user's button"

    told = run_tool(:add_grocery_list, assistant_chat(@alice), name: "Lista spesa")
    assert_match "already in use: add items with update_record", told[:error]
  end

  test "nothing in use: update_record says so, and add_grocery_list starts one" do
    told = run_tool(:update_record, @chat, items: [ { ingredient: "Tonno" } ])
    assert_match "no grocery_list in use", told.to_s

    assert_equal "saved", run_tool(:add_grocery_list, assistant_chat(@alice), name: "Lista della spesa", items: [ { ingredient: "Tonno" } ]).dig(:data, :status)
    assert GroceryList.exists?(profile: @alice, name: "Lista della spesa")
  end

  test "the context names the lists in use, with what is left to buy" do
    list!("Lista spesa", "Latte", "Uova")
    assert_includes Assistant::Context.new(@chat).to_prompt, "Grocery lists in use: \"Lista spesa\" (2 to buy)."
  end
end
