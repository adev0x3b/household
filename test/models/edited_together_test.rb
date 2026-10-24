# frozen_string_literal: true

require "test_helper"

# What more than one person can edit at once keeps a version, so a save
# made from an older copy is refused rather than undoing someone's change,
# and says who saved it last, so the refusal can name them.
class EditedTogetherTest < ActiveSupport::TestCase
  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
    @recipe = recipes(:roast_chicken)
  end

  def copy = Recipe.find(@recipe.id)

  test "every record with a version names who saved it" do
    Rails.application.eager_load!
    versioned = ApplicationRecord.descendants.select { !_1.abstract_class? && _1.table_exists? && _1.locking_enabled? }

    assert_not_empty versioned
    versioned.each do |model|
      assert_includes model, EditedTogether, "#{model} keeps a version, so a refusal of it names who saved"
      assert_includes model.column_names, "updated_by_id", "#{model.table_name}.updated_by_id"
    end
  end

  test "a save from an older copy is refused and changes nothing, even when only its lines changed" do
    alices, bobs = copy, copy
    bobs.edited_by(@bob).update!(name: "Bob's roast")

    assert_no_difference -> { @recipe.recipe_steps.count } do
      assert_not alices.edit_as(@alice) { alices.update(recipe_steps_attributes: [ { instruction: "Rest it" } ]) }
    end
    assert_equal "Bob's roast", @recipe.reload.name
  end

  test "a save names who made it, and a save that doesn't say leaves nobody named" do
    @recipe.edited_by(@bob).save!
    assert_equal @bob, @recipe.reload.updated_by

    assert_changes -> { @recipe.reload.lock_version }, "a form's save is checked even when nothing of its own changed" do
      assert @recipe.edit_as(@bob) { @recipe.save }
    end
    assert_equal @bob, @recipe.reload.updated_by, "the same person saving again is still named"

    copy.update!(description: "Roasted on Sundays")
    assert_nil @recipe.reload.updated_by
  end

  test "every write through a named copy names them" do
    @recipe.edited_by(@bob).update!(name: "Bob's roast")
    @recipe.update!(description: "Then the description")

    assert_equal @bob, @recipe.reload.updated_by
  end

  test "a refused save keeps what was typed, takes the row's version and names who saved meanwhile" do
    alices = copy
    copy.edited_by(@bob).update!(name: "Bob's roast")
    alices.name = "Alice's roast"
    assert_raises(ActiveRecord::StaleObjectError) { alices.edited_by(@alice).save! }

    alices.changed_meanwhile!(@alice)

    assert_equal "Alice's roast", alices.name
    assert_equal [ I18n.t("activerecord.errors.messages.changed_meanwhile_by", name: @bob.display_name) ], alices.errors.full_messages
    assert alices.edited_by(@alice).save, "saving again keeps what was typed"
    assert_equal "Alice's roast", @recipe.reload.name
  end

  test "the refusal says when the other save was one's own, or nobody's" do
    mine = copy
    copy.edited_by(@alice).update!(name: "From the other window")
    mine.changed_meanwhile!(@alice)
    assert_equal [ I18n.t("activerecord.errors.messages.changed_meanwhile_by_you") ], mine.errors.full_messages

    unnamed = copy
    copy.update!(name: "From a job")
    unnamed.changed_meanwhile!(@alice)
    assert_equal [ I18n.t("activerecord.errors.messages.changed_meanwhile") ], unnamed.errors.full_messages
  end

  test "a refused save of something deleted meanwhile is told it is gone" do
    alices = copy
    copy.destroy!

    assert_raises(ActiveRecord::RecordNotFound) { alices.changed_meanwhile!(@alice) }
  end

  test "what a day or a series holds moves its version when it changes" do
    day = occurrences(:bloodwork_done)
    assert_changes -> { day.reload.lock_version } do
      lab_test_result_entries(:glucose).update!(value: "101")
    end

    series = events(:water_the_plants)
    assert_changes -> { series.reload.lock_version } do
      series.event_slots.create!(time: "08:00", position: 0)
    end
    assert_changes -> { series.reload.lock_version } do
      series.details.update!(priority: :high)
    end
  end

  test "a change to what it holds is no edit from an older copy, even through one" do
    older = Event.find(events(:water_the_plants).id)
    events(:water_the_plants).update!(title: "Water everything")

    assert_nothing_raised { older.details.update!(priority: :high) }
  end

  test "what a done day keeps when its series changes, where its unsaved days start, and a new message, move no version" do
    series = events(:water_the_plants)
    done = day!(series, date: Date.new(2026, 3, 9), status: :completed)
    assert_no_changes -> { done.reload.lock_version } do
      series.update!(title: "Water everything")
    end
    assert_equal "Water the plants", done.reload.title

    assert_no_changes -> { series.reload.lock_version }, "the first day nothing is stored about is no edit of its series" do
      first = assert_changes(-> { series.reload.unsaved_from }) { day!(series, date: series.starts_on, status: :completed) }
      first.destroy!
      assert_equal series.starts_on, series.reload.unsaved_from
    end

    chat = conversations(:example_chat)
    assert_no_changes -> { chat.reload.lock_version } do
      send_message(chat, @bob)
    end
  end
end
