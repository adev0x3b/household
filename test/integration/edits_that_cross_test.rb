# frozen_string_literal: true

require "test_helper"

# Two people with the same thing open: the form goes back with the version
# it was drawn at, and a save made after someone else's is refused on the
# form, naming them, with what was typed kept. Saving again keeps it.
class EditsThatCrossTest < ActionDispatch::IntegrationTest
  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
    sign_in @alice
  end

  test "a recipe's form carries its version, and a save after a housemate's is refused naming them" do
    recipe = recipes(:roast_chicken)
    get edit_recipe_path(recipe), as: :turbo_stream
    assert_select "input[type=hidden][name='recipe[lock_version]'][value='0']"

    saved_by_bob(recipe, name: "Bob's roast")
    patch recipe_path(recipe), as: :turbo_stream, params: { recipe: { name: "Alice's roast", lock_version: 0 } }

    assert_crossed_by_bob(recipe, typed: "Alice's roast")
    assert_equal "Bob's roast", recipe.reload.name
  end

  test "saving again after the refusal keeps what was typed" do
    recipe = recipes(:roast_chicken)
    saved_by_bob(recipe, name: "Bob's roast")
    patch recipe_path(recipe), as: :turbo_stream, params: { recipe: { name: "Alice's roast", lock_version: 0 } }
    version = css_select("input[name='recipe[lock_version]']").first["value"]

    patch recipe_path(recipe), as: :turbo_stream, params: { recipe: { name: "Alice's roast", lock_version: version } }

    assert_response :see_other
    assert_equal "Alice's roast", recipe.reload.name
    assert_equal @alice, recipe.updated_by
  end

  test "a form that lists what was typed comes back with that over what the housemate saved" do
    recipe = recipes(:roast_chicken)
    saved_by_bob(recipe, name: "Bob's roast")
    drawn = { name: "Sunday Roast Chicken", description: "For guests", lock_version: 0 }

    patch recipe_path(recipe), as: :turbo_stream, params: { recipe: drawn, typed_fields: [ "recipe[description]" ] }

    assert_crossed_by_bob(recipe, typed: "Bob's roast")
    assert_select "textarea[name='recipe[description]']", text: "For guests"
    assert_select "input[type=hidden][name='typed_fields[]'][value='recipe[description]']"

    patch recipe_path(recipe), as: :turbo_stream, params: {
      recipe: { name: "Bob's roast", description: "For guests", lock_version: recipe.reload.lock_version },
      typed_fields: [ "recipe[description]" ]
    }
    assert_response :see_other
    assert_equal [ "Bob's roast", "For guests" ], [ recipe.reload.name, recipe.description ]
  end

  test "a form with nothing typed in it comes back as the housemate saved it" do
    recipe = recipes(:roast_chicken)
    saved_by_bob(recipe, name: "Bob's roast")

    patch recipe_path(recipe), as: :turbo_stream, params: { recipe: { name: "Sunday Roast Chicken", lock_version: 0 }, typed_fields: [ "" ] }

    assert_crossed_by_bob(recipe, typed: "Bob's roast")
  end

  test "lines left alone come back as the housemate saved them" do
    recipe = recipes(:roast_chicken)
    bobs = Recipe.find(recipe.id)
    assert bobs.edit_as(@bob) { bobs.update(recipe_steps_attributes: [ { instruction: "Rest it" } ]) }

    patch recipe_path(recipe), as: :turbo_stream, params: { recipe: { name: "Alice's roast", lock_version: 0 }, typed_fields: [ "recipe[name]" ] }

    assert_response :unprocessable_content
    assert_select "input[name='recipe[name]'][value=?]", "Alice's roast"
    assert_select "textarea", text: "Rest it"
  end

  test "an item's store section, which is its ingredient's, comes back as chosen" do
    item = grocery_list_items(:flour_item)
    saved_by_bob(item, quantity: 2)

    patch grocery_list_item_path(item), as: :turbo_stream, params: {
      grocery_list_item: { quantity: "1", category: "bakery", lock_version: 0 }, typed_fields: [ "grocery_list_item[category]" ]
    }

    assert_crossed_by_bob(item)
    assert_select "input[name='grocery_list_item[quantity]'][value='2']"
    assert_select "select[name='grocery_list_item[category]'] option[selected][value='bakery']"
    assert_not_equal "bakery", item.ingredient.reload.category, "nothing was saved"
  end

  test "a recipe whose lines alone changed is refused too" do
    recipe = recipes(:roast_chicken)
    saved_by_bob(recipe, name: "Bob's roast")

    assert_no_difference -> { recipe.recipe_steps.count } do
      patch recipe_path(recipe), as: :turbo_stream, params: { recipe: { lock_version: 0, recipe_steps_attributes: { "0" => { instruction: "Rest it" } } } }
    end
    assert_crossed_by_bob(recipe)
  end

  test "one's own save in another window is told as such" do
    recipe = recipes(:roast_chicken)
    recipe.edited_by(@alice).update!(name: "From the other window")

    patch recipe_path(recipe), as: :turbo_stream, params: { recipe: { name: "From this one", lock_version: 0 } }

    assert_response :unprocessable_content
    assert_form_error I18n.t("activerecord.errors.messages.changed_meanwhile_by_you")
  end

  test "a shared collection" do
    collection = collections(:b12)
    saved_by_bob(collection, name: "Bob's B12")
    patch collection_path(collection), as: :turbo_stream, params: { collection: { name: "Alice's B12", lock_version: 0 } }

    assert_crossed_by_bob(collection, typed: "Alice's B12")
    assert_equal "Bob's B12", collection.reload.name
  end

  test "a shared grocery list and an item on it" do
    list = grocery_lists(:weekly_shop)
    saved_by_bob(list, name: "Bob's shop")
    patch grocery_list_path(list), as: :turbo_stream, params: { grocery_list: { name: "Alice's shop", lock_version: 0 } }
    assert_crossed_by_bob(list, typed: "Alice's shop")
    assert_equal "Bob's shop", list.reload.name

    item = grocery_list_items(:flour_item)
    saved_by_bob(item, quantity: 2)
    patch grocery_list_item_path(item), as: :turbo_stream, params: { grocery_list_item: { quantity: "3", lock_version: 0 } }
    assert_crossed_by_bob(item)
    assert_equal 2, item.reload.quantity
  end

  test "a purchase for a shared therapy" do
    purchase = supply_purchase!(profile: @alice, name: "Cobalamin vial", collection: collections(:b12))
    saved_by_bob(purchase, quantity_remaining: 4)
    patch supply_purchase_path(purchase), as: :turbo_stream, params: { supply_purchase: { quantity_remaining: "7", lock_version: 0 } }

    assert_crossed_by_bob(purchase)
    assert_equal 4, purchase.reload.quantity_remaining
  end

  test "the household's conversation's name" do
    chat = conversations(:example_chat)
    saved_by_bob(chat, name: "Bob's house")
    patch conversation_path(chat), as: :turbo_stream, params: { conversation: { name: "Alice's house", lock_version: 0 } }

    assert_crossed_by_bob(chat, typed: "Alice's house")
    assert_equal "Bob's house", chat.reload.name
  end

  test "a day's form carries the day's version and its series'" do
    series = events(:water_the_plants) # Mondays from 2026-03-02
    get edit_event_day_path(series, "2026-03-16"), as: :turbo_stream
    assert_select "input[type=hidden][name='task[series_lock_version]'][value='0']"
    assert_select "input[name='task[lock_version]']", 0, "a day nothing was stored about has no version of its own"

    day = day!(series, date: Date.new(2026, 3, 16))
    get edit_event_day_path(series, "2026-03-16"), as: :turbo_stream
    assert_select "input[type=hidden][name='task[lock_version]'][value=?]", day.lock_version.to_s
  end

  test "a day saved after its series was is refused naming who saved it, and saving again keeps it" do
    series = events(:water_the_plants)
    day_saved_by_bob(series, "2026-03-23", title: "Water everything", apply_to: "series")

    patch event_day_path(series, "2026-03-16"), as: :turbo_stream, params: { task: { title: "Water the herbs", series_lock_version: 0 } }

    assert_response :unprocessable_content
    assert_form_error I18n.t("activerecord.errors.messages.changed_meanwhile_by", name: @bob.display_name)
    assert_select "input[name='task[title]'][value='Water the herbs']"
    assert_nil series.occurrences.find_by(date: Date.new(2026, 3, 16)), "nothing was stored"
    version = css_select("input[name='task[series_lock_version]']").first["value"]
    assert_equal series.reload.lock_version.to_s, version

    patch event_day_path(series, "2026-03-16"), as: :turbo_stream, params: { task: { title: "Water the herbs", series_lock_version: version } }
    assert_response :success
    assert_equal "Water the herbs", series.occurrence_on(Date.new(2026, 3, 16)).title
  end

  test "a day's form that lists what was typed comes back with that over the series as it was saved" do
    series = events(:water_the_plants)
    day_saved_by_bob(series, "2026-03-23", title: "Water everything", apply_to: "series")

    patch event_day_path(series, "2026-03-16"), as: :turbo_stream, params: {
      task: { title: "Water the plants", notes: "Mind the basil", series_lock_version: 0 }, typed_fields: [ "task[notes]" ]
    }

    assert_response :unprocessable_content
    assert_select "input[name='task[title]'][value='Water everything']"
    assert_select "textarea[name='task[notes]']", text: "Mind the basil"
    assert_select "input[type=hidden][name='typed_fields[]'][value='task[notes]']"
  end

  test "another day of the series saved meanwhile crosses nothing" do
    series = events(:water_the_plants)
    day = day!(series, date: Date.new(2026, 3, 16))
    day_saved_by_bob(series, "2026-03-23", title: "Just the roses")

    versions = { lock_version: day.lock_version, series_lock_version: series.reload.lock_version }
    patch event_day_path(series, "2026-03-16"), as: :turbo_stream, params: { task: { title: "Water the herbs", **versions } }

    assert_response :success
    assert_equal "Water the herbs", day.reload.title
  end

  test "a day stored meanwhile, or done meanwhile, is refused" do
    series = events(:water_the_plants)
    day_saved_by_bob(series, "2026-03-16", title: "Just the roses")

    patch event_day_path(series, "2026-03-16"), as: :turbo_stream, params: { task: { title: "Water the herbs", series_lock_version: 0 } }
    assert_response :unprocessable_content
    assert_form_error I18n.t("activerecord.errors.messages.changed_meanwhile_by", name: @bob.display_name)
    assert_equal "Just the roses", series.occurrence_on(Date.new(2026, 3, 16)).title

    day = series.occurrences.find_by!(date: Date.new(2026, 3, 16))
    drawn_at = day.lock_version
    Occurrence.find(day.id).edited_by(@bob).complete!
    versions = { lock_version: drawn_at, series_lock_version: series.reload.lock_version }
    patch event_day_path(series, "2026-03-16"), as: :turbo_stream, params: { task: { title: "Water the herbs", **versions } }
    assert_response :unprocessable_content
    assert_form_error I18n.t("activerecord.errors.messages.changed_meanwhile_by", name: @bob.display_name)
  end

  test "a press names who pressed, so a form it crosses can name them" do
    series = events(:water_the_plants)
    post event_day_completion_path(series, "2026-03-16"), as: :turbo_stream
    assert_equal @alice, series.occurrences.find_by!(date: Date.new(2026, 3, 16)).updated_by
    stored = day!(series, date: Date.new(2026, 3, 23))
    post event_day_completion_path(series, "2026-03-23"), as: :turbo_stream
    assert_equal @alice, stored.reload.updated_by

    item = grocery_list_items(:flour_item)
    post grocery_list_item_check_path(item), as: :turbo_stream
    assert_equal @alice, item.reload.updated_by
    delete grocery_list_item_check_path(item), as: :turbo_stream
    assert_equal @alice, item.reload.updated_by
  end

  test "a form held for its owner's OK is checked the same, and the request keeps no version" do
    series = events(:water_the_plants)
    day_saved_by_bob(series, "2026-03-23", title: "Water everything", apply_to: "series")
    params = { task: { title: "Water the herbs", series_lock_version: 0 } }

    stale = Occurrences::FormSave.for("Task").new(actor: @alice, params:, record: series.occurrence_on(Date.new(2026, 3, 16)))
    assert_not stale.valid_for_hold?
    assert_includes stale.record.errors.full_messages, I18n.t("activerecord.errors.messages.changed_meanwhile_by", name: @bob.display_name)

    params[:task][:series_lock_version] = series.reload.lock_version
    current = Occurrences::FormSave.for("Task").new(actor: @alice, params:, record: series.occurrence_on(Date.new(2026, 3, 16)))
    assert_predicate current, :valid_for_hold?
    assert_not_includes current.payload["task"].keys, "series_lock_version"
  end

  private

  # Bob's save of a day of the series, from his own form.
  def day_saved_by_bob(series, date, **fields)
    form = Occurrences::FormSave.for(series.type).new(actor: @bob, params: { series.model_name.param_key => fields }, record: series.occurrence_on(Date.parse(date)))
    assert form.save
  end

  # Bob's save from his own form, opened at the same version as Alice's.
  def saved_by_bob(record, **changes)
    bobs = record.class.find(record.id)
    assert bobs.edit_as(@bob) { bobs.update(changes) }
  end

  # Refused on the form, naming Bob, with what was typed kept and the
  # version Bob saved, so saving again is a choice.
  def assert_crossed_by_bob(record, typed: nil)
    key = record.model_name.param_key
    assert_response :unprocessable_content
    assert_form_error I18n.t("activerecord.errors.messages.changed_meanwhile_by", name: @bob.display_name)
    assert_select "input[type=hidden][name='#{key}[lock_version]'][value=?]", record.reload.lock_version.to_s
    assert_select "input[name='#{key}[name]'][value=?]", typed if typed
  end
end
