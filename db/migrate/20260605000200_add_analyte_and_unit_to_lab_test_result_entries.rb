# frozen_string_literal: true

class AddAnalyteAndUnitToLabTestResultEntries < ActiveRecord::Migration[8.1]
  def up
    add_reference :lab_test_result_entries, :analyte, null: true, foreign_key: true
    add_reference :lab_test_result_entries, :unit, null: true, foreign_key: true

    backfill_analytes_and_units
    dedupe_within_report_collisions

    remove_index :lab_test_result_entries, [ :lab_test_result_id, :key ]
    remove_column :lab_test_result_entries, :key
    remove_column :lab_test_result_entries, :unit

    change_column_null :lab_test_result_entries, :analyte_id, false
    add_index :lab_test_result_entries, [ :lab_test_result_id, :analyte_id ], unique: true,
                                                                              name: "index_lab_test_result_entries_on_lab_test_result_id_and_analyte"
  end

  def down
    add_column :lab_test_result_entries, :key, :string
    add_column :lab_test_result_entries, :unit, :string

    execute <<~SQL.squish
      UPDATE lab_test_result_entries
      SET key = analytes.name
      FROM analytes
      WHERE analytes.id = lab_test_result_entries.analyte_id
    SQL

    execute <<~SQL.squish
      UPDATE lab_test_result_entries
      SET unit = units.name
      FROM units
      WHERE units.id = lab_test_result_entries.unit_id
    SQL

    change_column_null :lab_test_result_entries, :key, false

    remove_index :lab_test_result_entries, [ :lab_test_result_id, :analyte_id ],
                 name: "index_lab_test_result_entries_on_lab_test_result_id_and_analyte"
    add_index :lab_test_result_entries, [ :lab_test_result_id, :key ], unique: true

    remove_reference :lab_test_result_entries, :analyte, foreign_key: true
    remove_reference :lab_test_result_entries, :unit, foreign_key: true
  end

  private

  def backfill_analytes_and_units
    say_with_time "Backfilling analyte_id/unit_id from key/unit" do
      keys = execute("SELECT DISTINCT key FROM lab_test_result_entries").map { |row| row["key"] }
      key_to_analyte_id = keys.index_with { |key| find_or_create_analyte_id(key) }

      raw_units = execute("SELECT DISTINCT unit FROM lab_test_result_entries WHERE unit IS NOT NULL").map { |row| row["unit"] }
      unit_to_unit_id = raw_units.index_with { |unit| find_or_create_unit_id(unit) }

      key_to_analyte_id.each do |key, analyte_id|
        execute(<<~SQL.squish)
          UPDATE lab_test_result_entries SET analyte_id = #{analyte_id}
          WHERE key = #{quote(key)}
        SQL
      end

      unit_to_unit_id.each do |unit, unit_id|
        execute(<<~SQL.squish)
          UPDATE lab_test_result_entries SET unit_id = #{unit_id}
          WHERE unit = #{quote(unit)}
        SQL
      end
    end
  end

  # Case/whitespace variants of the same key (e.g. "Glucose" and "glucose ")
  # normalize to the same analyte. If both happened to appear in the SAME
  # report, that would collide with the new unique index on
  # [lab_test_result_id, analyte_id]. Keep the earliest entry and drop the
  # rest — this is a data-cleanup edge case for pre-existing free-text rows,
  # not a path the app can create going forward (the form enforces this
  # uniqueness itself once analytes are real records).
  def dedupe_within_report_collisions
    duplicate_ids = execute(<<~SQL.squish).map { |row| row["id"] }
      SELECT a.id FROM lab_test_result_entries a
      JOIN lab_test_result_entries b
        ON a.lab_test_result_id = b.lab_test_result_id
       AND a.analyte_id = b.analyte_id
       AND a.id > b.id
    SQL

    return if duplicate_ids.empty?

    say "Dropping #{duplicate_ids.size} duplicate entr#{duplicate_ids.size == 1 ? 'y' : 'ies'} " \
        "that collided after case/whitespace normalization: #{duplicate_ids.join(', ')}"
    execute("DELETE FROM lab_test_result_entries WHERE id IN (#{duplicate_ids.join(', ')})")
  end

  def find_or_create_analyte_id(name)
    normalized = name.to_s.strip
    existing = execute("SELECT id FROM analytes WHERE LOWER(name) = #{quote(normalized.downcase)}").first
    return existing["id"] if existing

    execute("INSERT INTO analytes (name, created_at, updated_at) VALUES (#{quote(normalized)}, NOW(), NOW()) RETURNING id").first["id"]
  end

  def find_or_create_unit_id(name)
    normalized = name.to_s.strip
    existing = execute("SELECT id FROM units WHERE LOWER(name) = #{quote(normalized.downcase)}").first
    return existing["id"] if existing

    execute("INSERT INTO units (name, created_at, updated_at) VALUES (#{quote(normalized)}, NOW(), NOW()) RETURNING id").first["id"]
  end
end
