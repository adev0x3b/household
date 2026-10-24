# frozen_string_literal: true

require "test_helper"

# What the database itself holds the data to, beyond the models' checks.
class SchemaTest < ActiveSupport::TestCase
  def connection = ActiveRecord::Base.connection

  # What an index is sorted by, in order: its columns, or the parts of its
  # expression (`profile_id, lower(name)` is sorted by profile_id first, so
  # it serves a lookup on profile_id as well as an index of its own would).
  def keys(index)
    return index.columns if index.columns.is_a?(Array)

    index.columns.split(/,(?![^(]*\))/).map(&:strip)
  end

  # An index Postgres can use for any lookup on its leading columns: a b-tree
  # over the whole table, not a GIN index or one limited by a WHERE.
  def whole_btree?(index) = index.using.in?([ nil, :btree ]) && index.where.nil?

  # A longer index that starts with everything the other is sorted by.
  def covers?(longer, index)
    keys(longer).size > keys(index).size && keys(longer).first(keys(index).size) == keys(index)
  end

  # Two branches can each add a migration stamped the same minute. CI loads
  # the schema rather than migrating, so only this notices before a deploy's
  # db:migrate refuses them both.
  test "every migration has a version of its own" do
    versions = Dir[Rails.root.join("db/migrate/*.rb")].map { |file| File.basename(file)[/\A\d+/] }

    assert_empty versions.tally.select { |_, count| count > 1 }.keys, "migrations sharing a version"
  end

  # A key of several columns (a day's details, to the day and its series)
  # starts with the id of the row it points at, and an index on that finds
  # the rows a delete or an update there reaches.
  test "every foreign key has an index that starts with its column" do
    unindexed = connection.tables.flat_map do |table|
      leading = connection.indexes(table).map { keys(_1).first }
      connection.foreign_keys(table).map { Array(_1.column).first }.reject { leading.include?(_1) }.map { "#{table}.#{_1}" }
    end

    assert_empty unindexed, "a delete on the other side scans these tables"
  end

  test "no index is on columns another index of its table starts with" do
    covered = connection.tables.flat_map do |table|
      indexes = connection.indexes(table).select { whole_btree?(_1) }
      indexes.reject(&:unique).filter_map do |index|
        longer = indexes.find { covers?(_1, index) }
        "#{index.name} (#{longer.name} serves the same lookups)" if longer
      end
    end

    assert_empty covered, "each costs a write on every insert and update, and no read needs it"
  end

  test "every index has a name that says what it is on" do
    hashed = connection.tables.flat_map { connection.indexes(_1).map(&:name) }.grep(/\Aidx_on_/)

    assert_empty hashed, "Rails falls back to a hash when its own name is too long: name the index"
  end

  test "a day's details are keyed to the day and its series together" do
    Event.types.map { _1.details_class.table_name }.each do |table|
      key = connection.foreign_keys(table).find { _1.column == %w[occurrence_id event_id] }

      assert key, "#{table} pairs a day with its series in one key, so no row names another series' day"
      assert_equal [ %w[id event_id], :cascade, :cascade ], [ key.primary_key, key.on_delete, key.on_update ],
                   "#{table}'s rows go with their day, and follow it"
    end
  end

  test "a day's details can't name another series, and follow their day if it moves" do
    own = medication_details(:methotrexate_taken)
    error = assert_raises(ActiveRecord::InvalidForeignKey) do
      ActiveRecord::Base.transaction(requires_new: true) { own.update_columns(event_id: events(:cobalamin).id) }
    end
    assert_includes error.message, "medication_details_day_of_its_series"

    occurrences(:methotrexate_taken).update_columns(event_id: events(:cobalamin).id)
    assert_equal events(:cobalamin).id, own.reload.event_id
  end

  test "a day's records can't exist without their day" do
    Occurrence.children.each do |child|
      column = connection.columns(child.table_name).find { _1.name == child.foreign_key }
      assert_not column.null, "#{child.table_name}.#{child.foreign_key} is NOT NULL"
    end
  end
end
