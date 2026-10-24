# frozen_string_literal: true

require "test_helper"

# A line of an asked-for change reads in words: the field's name, an enum's
# value, a skipped day's reason and a day, in the reader's language.
class Links::Approvals::ChangeTest < ActiveSupport::TestCase
  test "an enum of the kind's details is worded, and its field named" do
    change = change_of(Task, "priority", "low", "high")

    assert_equal [ "Priority", "Low", "High" ], [ change.field, change.from, change.to ]
    I18n.with_locale(:it) { assert_equal I18n.t("tasks.priority.high"), change.to }
  end

  test "a skipped day's reason is worded like an enum" do
    assert_equal "Forgot", change_of(Medication, "skipped_reason", nil, "forgot").to
  end

  test "a day is localized, and a day that doesn't parse is shown as kept and reported" do
    assert_equal I18n.l(Date.new(2026, 10, 21), format: :long), change_of(Task, "date", nil, "2026-10-21").to

    assert_error_reported(Date::Error) { assert_equal "someday", change_of(Task, "date", nil, "someday").to }
  end

  test "an empty value before or after is nil" do
    change = change_of(Task, "notes", "", nil)

    assert_nil change.from
    assert_nil change.to
  end

  test "a field that is no column of the kind has its own words" do
    assert_equal I18n.t("links.approvals.fields.recurrence"), change_of(Task, "recurrence", nil, "Every week").field
    assert_equal "Every week", change_of(Task, "recurrence", nil, "Every week").to
  end

  private

  def change_of(kind, attribute, from, to)
    Links::Approvals::Change.new({ "attribute" => attribute, "from" => from, "to" => to }, kind: kind)
  end
end
