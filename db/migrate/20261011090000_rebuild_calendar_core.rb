# frozen_string_literal: true

# The calendar core, rebuilt in one cutover, released with the app stopped
# (docs/architecture/delivery.md, "A deploy without a gap"):
#
# * `events` becomes the series itself — an STI base (`type`) with the body
#   every series has (title, notes, location, start_time, duration_minutes,
#   starts_on, an RFC 5545 `rrule`, a `collection`) — instead of a thin
#   spine whose identity was "the earliest stored row";
# * one `occurrences` table holds every stored day of every kind (status,
#   completion, the slot, the overrides of the universal fields), in place
#   of six per-kind tables that each repeated the lifecycle;
# * each kind keeps only what it alone knows in `<kind>_details`: one row
#   for the series, one override row per day that differs;
# * `event_slots` and `event_exclusions` replace the two jsonb columns;
# * `medical_therapies` → `collections` (healthcare leaves the spine);
# * the counterparty mirror (a copied event kept in sync) goes: one row,
#   two readers;
# * what a dose plans to use moves to `supply_uses` on the series' details;
#   `supply_consumptions` keeps only what a day really drew.
#
# Every row is carried over; the asserts at the end refuse to commit a
# migration that lost one. Forward-only: the safeguards are the rehearsals
# (a rehearsal task on a copy of the data, since removed; then staging with
# production's data) and the dump taken right before it.
class RebuildCalendarCore < ActiveRecord::Migration[8.1]
  OLD_TABLES = {
    "Task" => "tasks", "Appointment" => "appointments", "Medication" => "medications",
    "Meal" => "meals", "LabTestResult" => "lab_test_results", "Transaction" => "transactions"
  }.freeze
  # Old per-kind status → the one enum (pending 0, in_progress 1, completed 2, cancelled 3, skipped 4).
  STATUS_SQL = "CASE r.status WHEN 0 THEN 0 WHEN 1 THEN 2 WHEN 2 THEN 3 WHEN 3 THEN 4 END"
  NOT_TAKEN_REASONS = %w[refused not_available held forgot other].freeze
  ANCHORS = { "CM" => [ 8, 0 ], "CD" => [ 12, 30 ], "CV" => [ 19, 30 ], "HS" => [ 22, 0 ] }.freeze
  PURCHASE_TYPES = %w[SupplyPurchase IngredientPurchase].freeze
  FIELD_RENAMES = {
    "provider" => "counterpart", "occurrence_date" => "date", "medical_therapy_id" => "collection_id",
    "not_taken_reason" => "skipped_reason", "scheduled_time" => "time", "timing_anchor" => "anchor",
    "description" => "notes"
  }.freeze
  CAPTURE_DAYS = 400

  def up
    # It renames and rewrites tables the previous version reads, which
    # strong_migrations refuses: this is the one deliberate exception,
    # released with the app stopped (docs/architecture/delivery.md).
    safety_assured do
      @report = {}
      preflight!
      rename_collections!
      create_new_tables!
      collapse_mirrors!
      drop_orphans!
      fill_series_bodies!
      convert_rrules!
      move_slots_and_exclusions!
      move_occurrences!
      move_details!
      move_supply_uses!
      move_children!
      rekey_reminders_links_and_notifications!
      rewrite_change_sets!
      drop_old!
      verify!
      say "cutover report: #{@report.inspect}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "the calendar core cutover is forward-only: restore the backup taken before it"
  end

  private

  # ── 1. Nothing is touched until every row is known to convert ──────────────
  def preflight!
    @old = {
      events: count("events"),
      recurring: count("events WHERE recurrence_rule IS NOT NULL"),
      mirrors: count("events WHERE source_event_id IS NOT NULL"),
      rows: OLD_TABLES.transform_values { |table| count(table) },
      mirror_rows: count("transactions WHERE event_id IN (SELECT id FROM events WHERE source_event_id IS NOT NULL)"),
      slots: select_value("SELECT COALESCE(SUM(jsonb_array_length(times_of_day)), 0) FROM events").to_i,
      lab_entries: count("lab_test_result_entries"),
      meal_consumptions: count("meal_consumptions"),
      meal_recipes: count("meal_recipes"),
      consumptions_drawn: count("supply_consumptions WHERE supply_purchase_id IS NOT NULL"),
      collections: count("medical_therapies"),
      collection_shares: count("medical_therapy_shares"),
      purchases_in_collection: count("supply_purchases WHERE medical_therapy_id IS NOT NULL"),
      approvals_with_record: count("link_approvals WHERE record_id IS NOT NULL"),
      counterparties: count("transactions WHERE counterparty_profile_id IS NOT NULL AND event_id NOT IN (SELECT id FROM events WHERE source_event_id IS NOT NULL)"),
      series_fees: count("transactions WHERE attachable_series_event_id IS NOT NULL OR attachable_type IN ('SupplyPurchase', 'IngredientPurchase')"),
      day_fees: count("transactions WHERE attachable_type IN (#{OLD_TABLES.keys.map { |k| quote(k) }.join(', ')})")
    }

    bad = select_values("SELECT id FROM events WHERE eventable_type NOT IN (#{OLD_TABLES.keys.map { |k| quote(k) }.join(', ')})")
    raise "events of an unknown kind: #{bad.inspect}" if bad.any?

    mirrors = select_rows("SELECT id, eventable_type FROM events WHERE source_event_id IS NOT NULL")
    not_money = mirrors.reject { |_, type| type == "Transaction" }
    raise "mirror events that aren't transactions: #{not_money.inspect}" if not_money.any?

    mirror_ids = mirrors.map(&:first)
    if mirror_ids.any?
      %w[event_shares event_reminders link_approvals].each do |table|
        n = count("#{table} WHERE event_id IN (#{mirror_ids.join(', ')})")
        raise "#{n} #{table} rows on mirror events; the collapse would lose them" if n.positive?
      end
    end

    @rules = {}
    @captured = {}
    select_rows("SELECT id, recurrence_rule, date FROM events WHERE recurrence_rule IS NOT NULL").each do |id, yaml, date|
      schedule = IceCube::Schedule.from_yaml(yaml)
      @rules[id] = single_rule_for(id, schedule)
      from = Date.parse(date.to_s)
      @captured[id] = days_between(schedule, from, from + CAPTURE_DAYS)
    end

    select_rows("SELECT id, excluded_dates FROM events WHERE jsonb_array_length(excluded_dates) > 0").each do |id, entries|
      JSON.parse(entries.to_s).each do |entry|
        day, time = entry.to_s.split("T")
        Date.parse(day)
        raise "event #{id}: unreadable exclusion #{entry.inspect}" if time && time !~ /\A\d{2}:\d{2}\z/
      end
    end
  end

  # The calendar days a schedule yields from one date to another: each
  # occurrence's date in its own offset, over a window a day wider at both
  # ends, kept between the two dates. A stored schedule carries the offset
  # of whoever made it (+02:00 on a laptop in summer, +00:00 in the UTC
  # containers); a window cut at the machine's midnight would add or drop a
  # day at its edges, depending on where the migration runs.
  def days_between(schedule, from, to)
    schedule.occurrences_between((from - 1).to_time, (to + 2).to_time).map(&:to_date).select { |day| day.between?(from, to) }
  end

  # One ice_cube rule per series. Several weekly rules of one interval (as
  # the seeds made them) merge into one BYDAY rule; anything else is refused.
  def single_rule_for(id, schedule)
    rules = schedule.recurrence_rules
    raise "event #{id}: a schedule without a rule" if rules.empty?
    return rules.first if rules.one?

    unless rules.all? { |rule| rule.is_a?(IceCube::WeeklyRule) } && rules.map { |rule| rule.to_hash[:interval] }.uniq.one?
      raise "event #{id}: #{rules.size} rules that don't merge into one RRULE"
    end
    raise "event #{id}: weekly rules with an end date don't merge" if rules.any?(&:until_time)

    days = rules.flat_map { |rule| Array(rule.to_hash.dig(:validations, :day)) }.uniq.sort
    IceCube::Rule.weekly(rules.first.to_hash[:interval]).day(*days)
  end

  # ── 2. Therapies become collections ─────────────────────────────────────────
  def rename_collections!
    rename_table :medical_therapies, :collections
    rename_column :collections, :description, :notes
    add_column :collections, :section, :string, null: false, default: "healthcare"
    add_index :collections, %i[profile_id section]

    rename_table :medical_therapy_shares, :collection_shares
    rename_column :collection_shares, :medical_therapy_id, :collection_id
    rename_column :supply_purchases, :medical_therapy_id, :collection_id
    rename_column :events, :medical_therapy_id, :collection_id
  end

  # ── 3. The new shape ────────────────────────────────────────────────────────
  def create_new_tables!
    change_table :events, bulk: true do |t|
      t.string :type
      t.string :title
      t.text :notes
      t.string :location
      t.time :start_time
      t.integer :duration_minutes
      t.text :rrule
    end
    rename_column :events, :date, :starts_on

    create_table :event_slots do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.time :time, null: false
      t.string :anchor
      t.integer :position, null: false, default: 0
      t.index %i[event_id time], unique: true
      t.index %i[event_id position], unique: true
    end

    create_table :event_exclusions do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.time :time
      t.index %i[event_id date time], unique: true, nulls_not_distinct: true
    end

    create_table :occurrences do |t|
      t.references :event, null: false, foreign_key: true
      t.date :date, null: false
      t.time :time
      t.string :anchor
      t.integer :status, null: false, default: 0
      t.datetime :completed_at
      t.string :skipped_reason
      t.string :title
      t.text :notes
      t.string :location
      t.time :start_time
      t.integer :duration_minutes
      t.timestamps
      t.index %i[event_id date time], unique: true, nulls_not_distinct: true
      t.index :date
      t.index %i[event_id status]
      t.check_constraint "skipped_reason IS NULL OR status = 4", name: "occurrences_skipped_reason_with_skipped"
    end

    create_details_table :task_details do |t|
      t.integer :priority
      t.check_constraint "occurrence_id IS NOT NULL OR priority IS NOT NULL", name: "task_details_series_row_complete"
    end

    create_details_table :appointment_details do |t|
      t.integer :kind
      t.string :counterpart
      t.check_constraint "occurrence_id IS NOT NULL OR kind IS NOT NULL", name: "appointment_details_series_row_complete"
    end

    create_details_table :medication_details do |t|
      t.integer :kind
      t.integer :area
      t.integer :side
      t.decimal :quantity, precision: 10, scale: 2
      t.string :unit
      t.decimal :pill_count, precision: 10, scale: 3
      t.check_constraint "occurrence_id IS NOT NULL OR kind IS NOT NULL", name: "medication_details_series_row_complete"
    end

    create_details_table :meal_details do |t|
      t.integer :kind
      t.integer :meal_type
      t.check_constraint "occurrence_id IS NOT NULL OR kind IS NOT NULL", name: "meal_details_series_row_complete"
    end

    create_details_table :lab_test_result_details

    create_details_table :transaction_details do |t|
      t.integer :kind
      t.integer :category
      t.bigint :amount_cents
      t.string :currency, limit: 3
      t.integer :payment_method
      t.string :counterparty
      t.references :counterparty_profile, foreign_key: { to_table: :profiles }
      t.references :about, polymorphic: true
      t.check_constraint "amount_cents IS NULL OR amount_cents <> 0", name: "transaction_details_amount_cents_non_zero"
      t.check_constraint "currency IS NULL OR currency ~ '^[A-Z]{3}$'", name: "transaction_details_currency_format"
      t.check_constraint "kind IS NULL OR amount_cents IS NULL OR (kind = 0 AND amount_cents > 0) OR (kind = 1 AND amount_cents < 0)", name: "transaction_details_kind_matches_amount_sign"
      t.check_constraint "occurrence_id IS NOT NULL OR (kind IS NOT NULL AND category IS NOT NULL AND amount_cents IS NOT NULL AND currency IS NOT NULL AND payment_method IS NOT NULL)", name: "transaction_details_series_row_complete"
      t.check_constraint "occurrence_id IS NULL OR counterparty_profile_id IS NULL", name: "transaction_details_counterparty_on_series"
    end

    create_table :supply_uses do |t|
      t.references :medication_details, null: false, foreign_key: { on_delete: :cascade }
      t.references :supply, null: false, foreign_key: true
      t.decimal :quantity, precision: 10, scale: 3, null: false
      t.index %i[medication_details_id supply_id], unique: true
    end

    execute "CREATE TEMP TABLE occurrence_map (old_table text NOT NULL, old_id bigint NOT NULL, occurrence_id bigint NOT NULL, PRIMARY KEY (old_table, old_id))"
    execute "CREATE TEMP TABLE templates (event_id bigint PRIMARY KEY, old_table text NOT NULL, row_id bigint NOT NULL)"
  end

  def create_details_table(name)
    create_table name do |t|
      t.references :event, null: false, foreign_key: true
      t.references :occurrence, foreign_key: { on_delete: :cascade }
      yield t if block_given?
      t.timestamps
      t.index %i[event_id occurrence_id], unique: true, nulls_not_distinct: true
    end
  end

  # ── 4. One payment, two readers: the copies go ───────────────────────────
  def collapse_mirrors!
    execute "CREATE TEMP TABLE mirror_events AS SELECT id FROM events WHERE source_event_id IS NOT NULL"
    execute "UPDATE transactions SET mirror_transaction_id = NULL WHERE mirror_transaction_id IN (SELECT id FROM transactions WHERE event_id IN (SELECT id FROM mirror_events))"
    execute "UPDATE notifications SET subject_type = NULL, subject_id = NULL WHERE subject_type = 'Event' AND subject_id IN (SELECT id FROM mirror_events)"
    execute "UPDATE transactions SET attachable_series_event_id = NULL WHERE attachable_series_event_id IN (SELECT id FROM mirror_events)"
    execute "DELETE FROM transactions WHERE event_id IN (SELECT id FROM mirror_events)"
    execute "UPDATE events SET source_event_id = NULL"
    execute "DELETE FROM events WHERE id IN (SELECT id FROM mirror_events)"
    @report[:mirrors_collapsed] = @old[:mirrors]
  end

  # ── 5. A series with no stored day at all has nothing to carry ──────────
  def drop_orphans!
    conditions = OLD_TABLES.map { |type, table| "(e.eventable_type = #{quote(type)} AND NOT EXISTS (SELECT 1 FROM #{table} r WHERE r.event_id = e.id))" }
    execute "CREATE TEMP TABLE orphan_events AS SELECT e.id FROM events e WHERE #{conditions.join(' OR ')}"
    @report[:orphans_dropped] = count("orphan_events")
    return if @report[:orphans_dropped].zero?

    execute "DELETE FROM event_reminder_deliveries WHERE event_reminder_id IN (SELECT id FROM event_reminders WHERE event_id IN (SELECT id FROM orphan_events))"
    execute "DELETE FROM event_reminders WHERE event_id IN (SELECT id FROM orphan_events)"
    execute "DELETE FROM event_shares WHERE event_id IN (SELECT id FROM orphan_events)"
    execute "DELETE FROM link_approvals WHERE event_id IN (SELECT id FROM orphan_events)"
    execute "UPDATE transactions SET attachable_series_event_id = NULL WHERE attachable_series_event_id IN (SELECT id FROM orphan_events)"
    execute "UPDATE notifications SET subject_type = NULL, subject_id = NULL WHERE subject_type = 'Event' AND subject_id IN (SELECT id FROM orphan_events)"
    execute "DELETE FROM events WHERE id IN (SELECT id FROM orphan_events)"
  end

  # ── 6. The series gets its body from its earliest stored day ─────────────
  def fill_series_bodies!
    execute "UPDATE events SET type = eventable_type"
    OLD_TABLES.each do |_type, table|
      order = table == "medications" ? "event_id, occurrence_date, scheduled_time NULLS FIRST, id" : "event_id, occurrence_date, id"
      execute "INSERT INTO templates (event_id, old_table, row_id) SELECT DISTINCT ON (event_id) event_id, #{quote(table)}, id FROM #{table} ORDER BY #{order}"
    end

    body = {
      "tasks" => "title = r.title, notes = r.description",
      "appointments" => "title = r.title, notes = r.notes, location = r.location, start_time = r.start_time",
      "medications" => "title = r.name",
      "meals" => "title = r.title, notes = r.notes",
      "lab_test_results" => "title = r.title, notes = r.notes",
      "transactions" => "title = r.title, notes = r.description"
    }
    body.each do |table, set|
      execute "UPDATE events e SET #{set} FROM #{table} r JOIN templates t ON t.row_id = r.id AND t.old_table = #{quote(table)} WHERE e.id = t.event_id"
    end
  end

  # ── 7. The rule becomes an RRULE line that reproduces the same days ────────
  def convert_rrules!
    suppress_messages do
      checked = 0
      @rules.each do |id, rule|
        starts_on = select_value("SELECT starts_on FROM events WHERE id = #{id}")
        next if starts_on.nil? # a mirror or an orphan, gone

        ical = rule.to_ical
        rebuilt = IceCube::Schedule.new(Date.parse(starts_on.to_s).to_time)
        rebuilt.add_recurrence_rule(IceCube::Rule.from_ical(ical))
        from = Date.parse(starts_on.to_s)
        dates = days_between(rebuilt, from, from + CAPTURE_DAYS)
        raise "event #{id}: #{ical.inspect} doesn't reproduce the schedule's days" unless dates == @captured[id]

        execute "UPDATE events SET rrule = #{quote(ical)} WHERE id = #{id}"
        checked += 1
      end
      @report[:rrules_checked] = checked
    end
  end

  # ── 8. Doses of the day and deleted days become rows ──────────────────────
  def move_slots_and_exclusions!
    suppress_messages do
      select_rows("SELECT id, times_of_day FROM events WHERE jsonb_array_length(times_of_day) > 0").each do |id, entries|
        expand_slots(JSON.parse(entries.to_s)).each_with_index do |(time, anchor), position|
          execute "INSERT INTO event_slots (event_id, time, anchor, position) VALUES (#{id}, #{quote(time)}, #{quote(anchor)}, #{position})"
        end
      end

      select_rows("SELECT id, excluded_dates FROM events WHERE jsonb_array_length(excluded_dates) > 0").each do |id, entries|
        JSON.parse(entries.to_s).map(&:to_s).uniq.each do |entry|
          day, time = entry.split("T")
          execute "INSERT INTO event_exclusions (event_id, date, time) VALUES (#{id}, #{quote(day)}, #{quote(time)}) ON CONFLICT DO NOTHING"
        end
      end
      @report[:slots] = count("event_slots")
      @report[:exclusions] = count("event_exclusions")
    end
  end

  # Events::TimesOfDay.expand, copied so the migration owns its rules.
  def expand_slots(list)
    list.filter_map do |entry|
      entry = entry.to_s
      if ANCHORS.key?(entry)
        [ format("%02d:%02d", *ANCHORS[entry]), entry ]
      elsif entry.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/)
        [ entry, nil ]
      end
    end.uniq(&:first).sort_by(&:first)
  end

  # ── 9. Every stored day becomes an occurrence; the map remembers which ────
  def move_occurrences!
    columns = {
      "tasks" => { title: "r.title", notes: "r.description", location: "NULL", start_time: "NULL", status: "r.status" },
      "appointments" => { title: "r.title", notes: "r.notes", location: "r.location", start_time: "r.start_time", status: STATUS_SQL },
      "medications" => { title: "r.name", notes: "NULL", location: "NULL", start_time: "NULL", status: STATUS_SQL },
      "meals" => { title: "r.title", notes: "r.notes", location: "NULL", start_time: "NULL", status: STATUS_SQL },
      "lab_test_results" => { title: "r.title", notes: "r.notes", location: "NULL", start_time: "NULL", status: STATUS_SQL },
      "transactions" => { title: "r.title", notes: "r.description", location: "NULL", start_time: "NULL", status: STATUS_SQL }
    }
    reasons = NOT_TAKEN_REASONS.each_with_index.map { |reason, index| "WHEN #{index} THEN #{quote(reason)}" }.join(" ")

    columns.each do |table, c|
      time = table == "medications" ? "r.scheduled_time" : "NULL::time"
      anchor = table == "medications" ? "r.timing_anchor" : "NULL"
      reason = table == "medications" ? "CASE WHEN r.status = 3 THEN (CASE r.not_taken_reason #{reasons} END) END" : "NULL"
      execute <<~SQL
        WITH ins AS (
          INSERT INTO occurrences (event_id, date, time, anchor, status, completed_at, skipped_reason, title, notes, location, start_time, created_at, updated_at)
          SELECT r.event_id, r.occurrence_date, #{time}, #{anchor}, #{c[:status]}, r.completed_at, #{reason},
                 NULLIF(#{c[:title]}, e.title), NULLIF(#{c[:notes]}, e.notes), NULLIF(#{c[:location]}, e.location), NULLIF(#{c[:start_time]}, e.start_time),
                 r.created_at, r.updated_at
          FROM #{table} r JOIN events e ON e.id = r.event_id
          RETURNING id, event_id, date, time
        )
        INSERT INTO occurrence_map (old_table, old_id, occurrence_id)
        SELECT #{quote(table)}, r.id, ins.id
        FROM ins JOIN #{table} r ON r.event_id = ins.event_id AND r.occurrence_date = ins.date AND (#{time} IS NOT DISTINCT FROM ins.time)
      SQL
    end
    @report[:occurrences] = count("occurrences")
  end

  # ── 10/11. The kind's own fields: a series row, an override where a day differs
  def move_details!
    series_row! "tasks", "task_details", "priority", "r.priority"
    override_rows! "tasks", "task_details", %w[priority]

    series_row! "appointments", "appointment_details", "kind, counterpart", "0, r.provider"
    override_rows! "appointments", "appointment_details", %w[provider], as: { "provider" => "counterpart" }

    series_row! "medications", "medication_details", "kind, area, side, quantity, unit, pill_count", "r.kind, r.area, r.side, r.quantity, r.unit, r.pill_count"
    override_rows! "medications", "medication_details", %w[kind area side quantity unit pill_count]

    series_row! "meals", "meal_details", "kind, meal_type", "r.kind, r.meal_type"
    override_rows! "meals", "meal_details", %w[kind meal_type]

    series_row! "lab_test_results", "lab_test_result_details", nil, nil

    series_about = <<~SQL.squish
      CASE WHEN r.attachable_series_event_id IS NOT NULL THEN 'Event'
           WHEN r.attachable_type IN ('SupplyPurchase', 'IngredientPurchase') THEN r.attachable_type END,
      CASE WHEN r.attachable_series_event_id IS NOT NULL THEN r.attachable_series_event_id
           WHEN r.attachable_type IN ('SupplyPurchase', 'IngredientPurchase') THEN r.attachable_id END
    SQL
    series_row! "transactions", "transaction_details",
                "kind, category, amount_cents, currency, payment_method, counterparty, counterparty_profile_id, about_type, about_id",
                "r.kind, r.category, r.amount_cents, r.currency, r.payment_method, r.counterparty, r.counterparty_profile_id, #{series_about}"
    # A day's fee pins the day it is about — on every row attached to a day,
    # the template's included — besides any money field that differs.
    money = %w[kind category amount_cents currency payment_method counterparty]
    day_about = OLD_TABLES.map { |type, table| "WHEN r.attachable_type = #{quote(type)} THEN (SELECT occurrence_id FROM occurrence_map m WHERE m.old_table = #{quote(table)} AND m.old_id = r.attachable_id)" }.join(" ")
    kinds = OLD_TABLES.keys.map { |k| quote(k) }.join(", ")
    execute <<~SQL
      INSERT INTO transaction_details (event_id, occurrence_id, #{money.join(', ')}, about_type, about_id, created_at, updated_at)
      SELECT r.event_id, m.occurrence_id, #{money.map { |col| differs(col) }.join(', ')},
             CASE WHEN r.attachable_type IN (#{kinds}) THEN 'Occurrence' END,
             CASE #{day_about} END,
             r.created_at, r.updated_at
      FROM transactions r
      JOIN occurrence_map m ON m.old_table = 'transactions' AND m.old_id = r.id
      JOIN templates t ON t.event_id = r.event_id AND t.old_table = 'transactions'
      JOIN transactions s ON s.id = t.row_id
      WHERE r.attachable_type IN (#{kinds})
         OR (r.id <> t.row_id AND (#{money.map { |col| "#{differs(col)} IS NOT NULL" }.join(' OR ')}))
    SQL

    @report[:series_details] = OLD_TABLES.values.sum { |table| count("#{table.singularize}_details WHERE occurrence_id IS NULL") }
    @report[:override_details] = OLD_TABLES.values.sum { |table| count("#{table.singularize}_details WHERE occurrence_id IS NOT NULL") }
  end

  # A day's value where it differs from the series', else NULL (= inherit).
  # A NULL on a stored day was never a value of its own — the old copies
  # carried only some fields — so it inherits too.
  def differs(column) = "CASE WHEN r.#{column} IS NOT NULL AND r.#{column} IS DISTINCT FROM s.#{column} THEN r.#{column} END"

  def series_row!(table, details, columns, values)
    cols = [ "event_id", "occurrence_id", columns, "created_at", "updated_at" ].compact.join(", ")
    vals = [ "r.event_id", "NULL", values, "r.created_at", "r.updated_at" ].compact.join(", ")
    execute "INSERT INTO #{details} (#{cols}) SELECT #{vals} FROM #{table} r JOIN templates t ON t.row_id = r.id AND t.old_table = #{quote(table)}"
  end

  def override_rows!(table, details, columns, as: {})
    targets = columns.map { |col| as.fetch(col, col) }
    execute <<~SQL
      INSERT INTO #{details} (event_id, occurrence_id, #{targets.join(', ')}, created_at, updated_at)
      SELECT r.event_id, m.occurrence_id, #{columns.map { |col| differs(col) }.join(', ')}, r.created_at, r.updated_at
      FROM #{table} r
      JOIN occurrence_map m ON m.old_table = #{quote(table)} AND m.old_id = r.id
      JOIN templates t ON t.event_id = r.event_id AND t.old_table = #{quote(table)}
      JOIN #{table} s ON s.id = t.row_id
      WHERE r.id <> t.row_id AND (#{columns.map { |col| "#{differs(col)} IS NOT NULL" }.join(' OR ')})
    SQL
  end

  # ── 12. What a dose plans to use vs what it drew ─────────────────────────
  def move_supply_uses!
    suppress_messages do
      plans = Hash.new { |h, k| h[k] = Hash.new(0) }
      select_rows("SELECT medication_id, supply_id, quantity FROM supply_consumptions WHERE medication_id IS NOT NULL").each do |medication_id, supply_id, quantity|
        plans[medication_id][supply_id] += BigDecimal(quantity.to_s)
      end
      templates = select_rows("SELECT event_id, row_id FROM templates WHERE old_table = 'medications'").to_h
      rows_by_event = select_rows("SELECT event_id, id FROM medications").group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

      rows_by_event.each do |event_id, row_ids|
        template_id = templates.fetch(event_id)
        insert_uses!(details_id_for(event_id, nil), plans[template_id])
        (row_ids - [ template_id ]).each do |row_id|
          next if plans[row_id] == plans[template_id]

          occurrence_id = select_value("SELECT occurrence_id FROM occurrence_map WHERE old_table = 'medications' AND old_id = #{row_id}")
          insert_uses!(details_id_for(event_id, occurrence_id), plans[row_id])
        end
      end

      @report[:supply_uses] = count("supply_uses")
      execute "DELETE FROM supply_consumptions WHERE supply_purchase_id IS NULL"
    end
  end

  # The medication_details row of a series (occurrence nil) or of one of its
  # days, made if the move of fields didn't need one.
  def details_id_for(event_id, occurrence_id)
    where = occurrence_id ? "occurrence_id = #{occurrence_id}" : "occurrence_id IS NULL"
    select_value("SELECT id FROM medication_details WHERE event_id = #{event_id} AND #{where}") ||
      select_value("INSERT INTO medication_details (event_id, occurrence_id, created_at, updated_at) VALUES (#{event_id}, #{occurrence_id || 'NULL'}, NOW(), NOW()) RETURNING id")
  end

  def insert_uses!(details_id, plan)
    plan.each do |supply_id, quantity|
      next unless quantity.positive?

      execute "INSERT INTO supply_uses (medication_details_id, supply_id, quantity) VALUES (#{details_id}, #{supply_id}, #{quantity.to_s('F')})"
    end
  end

  # ── 13. Per-day children hang off the day; a meal's recipes off its details
  def move_children!
    rekey_child! "lab_test_result_entries", "lab_test_result_id", "lab_test_results", null: false
    add_index :lab_test_result_entries, %i[occurrence_id analyte_id], unique: true

    rekey_child! "supply_consumptions", "medication_id", "medications", null: false
    rekey_child! "meal_consumptions", "meal_id", "meals", null: false

    add_reference :meal_recipes, :meal_details, foreign_key: { on_delete: :cascade }
    templates = select_rows("SELECT event_id, row_id FROM templates WHERE old_table = 'meals'").to_h
    recipes = select_rows("SELECT meal_id, recipe_id FROM meal_recipes").group_by(&:first).transform_values { |pairs| pairs.map(&:last).sort }
    suppress_messages { rekey_meal_recipes!(templates, recipes) }
    raise "meal recipes left without a details row" if count("meal_recipes WHERE meal_details_id IS NULL").positive?

    remove_foreign_key :meal_recipes, :meals
    remove_column :meal_recipes, :meal_id
    change_column_null :meal_recipes, :meal_details_id, false
    add_index :meal_recipes, %i[meal_details_id recipe_id], unique: true
    @report[:meal_recipes] = count("meal_recipes")
  end

  def rekey_meal_recipes!(templates, recipes)
    select_rows("SELECT event_id, id FROM meals").group_by(&:first).each do |event_id, pairs|
      template_id = templates.fetch(event_id)
      series_details = select_value("SELECT id FROM meal_details WHERE event_id = #{event_id} AND occurrence_id IS NULL")
      execute "UPDATE meal_recipes SET meal_details_id = #{series_details} WHERE meal_id = #{template_id}"
      (pairs.map(&:last) - [ template_id ]).each do |row_id|
        if recipes.fetch(row_id, []) == recipes.fetch(template_id, [])
          execute "DELETE FROM meal_recipes WHERE meal_id = #{row_id}"
        else
          occurrence_id = select_value("SELECT occurrence_id FROM occurrence_map WHERE old_table = 'meals' AND old_id = #{row_id}")
          details_id = select_value("SELECT id FROM meal_details WHERE event_id = #{event_id} AND occurrence_id = #{occurrence_id}") ||
                       select_value("INSERT INTO meal_details (event_id, occurrence_id, created_at, updated_at) VALUES (#{event_id}, #{occurrence_id}, NOW(), NOW()) RETURNING id")
          execute "UPDATE meal_recipes SET meal_details_id = #{details_id} WHERE meal_id = #{row_id}"
        end
      end
    end
  end

  def rekey_child!(table, old_column, old_table, null:)
    add_reference table, :occurrence, foreign_key: true
    execute "UPDATE #{table} c SET occurrence_id = m.occurrence_id FROM occurrence_map m WHERE m.old_table = #{quote(old_table)} AND m.old_id = c.#{old_column}"
    raise "#{table}: rows whose #{old_column} maps to no day" if count("#{table} WHERE #{old_column} IS NOT NULL AND occurrence_id IS NULL").positive?

    remove_foreign_key table, old_table
    remove_column table, old_column
    change_column_null table, :occurrence_id, false if null
  end

  # ── 14. Reminders, grants, approvals, notifications ──────────────────────
  def rekey_reminders_links_and_notifications!
    rename_column :event_reminder_deliveries, :occurrence_date, :date
    rename_column :event_reminder_deliveries, :occurrence_time, :time
    rename_index :event_reminder_deliveries, "index_event_reminder_deliveries_on_reminder_and_occurrence", "index_event_reminder_deliveries_on_reminder_and_slot"

    rename_column :link_grants, :eventable_type, :event_type

    remove_index :link_approvals, name: "index_link_approvals_one_pending"
    rename_column :link_approvals, :eventable_type, :event_type
    rename_column :link_approvals, :occurrence_date, :date
    add_reference :link_approvals, :occurrence, foreign_key: { on_delete: :nullify }
    kinds = OLD_TABLES.map { |type, table| "WHEN a.event_type = #{quote(type)} THEN (SELECT occurrence_id FROM occurrence_map m WHERE m.old_table = #{quote(table)} AND m.old_id = a.record_id)" }.join(" ")
    execute "UPDATE link_approvals a SET occurrence_id = CASE #{kinds} END WHERE a.record_id IS NOT NULL"
    remove_column :link_approvals, :record_id
    add_index :link_approvals, %i[event_id date action_kind requester_id], unique: true, where: "status = 0 AND event_id IS NOT NULL", name: "index_link_approvals_one_pending"

    suppress_messages do
      select_rows("SELECT id, event_type, payload, preview FROM link_approvals").each do |id, type, payload, preview|
        payload = rename_payload(JSON.parse(payload.to_s), type)
        preview = JSON.parse(preview.to_s).map { |row| row.merge("attribute" => rename_field(row["attribute"], type)) }
        execute "UPDATE link_approvals SET payload = #{quote(payload.to_json)}, preview = #{quote(preview.to_json)} WHERE id = #{id}"
      end
    end

    execute "UPDATE notifications SET subject_type = 'Collection' WHERE subject_type = 'MedicalTherapy'"
    execute <<~SQL
      UPDATE notifications
      SET data = jsonb_strip_nulls((data - 'occurrence_date' - 'scheduled_time' - 'timing_anchor')
                 || jsonb_build_object('date', data->'occurrence_date', 'time', data->'scheduled_time', 'anchor', data->'timing_anchor'))
      WHERE data ?| array['occurrence_date', 'scheduled_time', 'timing_anchor']
    SQL
  end

  def rename_field(name, type)
    return "title" if name == "name" && type == "Medication"

    FIELD_RENAMES.fetch(name.to_s, name.to_s)
  end

  # A held form's params (per-kind key, "event", "transaction") or an
  # assistant op ("spec" with "fields"): the fields renamed, a fee's thing
  # mapped to its day.
  def rename_payload(payload, type)
    payload.to_h do |section, value|
      next [ section, value ] unless value.is_a?(Hash)

      if section == "spec"
        spec = value.dup
        spec["fields"] = rename_fields(spec["fields"], type) if spec["fields"].is_a?(Hash)
        if spec["ref"].to_s.match?(/\A\d+\z/) && (table = OLD_TABLES[spec["type"].to_s.camelize])
          mapped = select_value("SELECT occurrence_id FROM occurrence_map WHERE old_table = #{quote(table)} AND old_id = #{spec['ref'].to_i}")
          spec["ref"] = mapped.to_s if mapped
        end
        [ section, spec ]
      else
        [ section, rename_fields(value, type) ]
      end
    end
  end

  def rename_fields(fields, type)
    out = {}
    fields.each do |key, value|
      case key
      when "attachable_series_event_id" then next
      when "attachable_type" then out["about_type"] = OLD_TABLES.key?(value.to_s) ? "Occurrence" : value
      when "attachable_id"
        table = OLD_TABLES[fields["attachable_type"].to_s]
        out["about_id"] = table ? select_value("SELECT occurrence_id FROM occurrence_map WHERE old_table = #{quote(table)} AND old_id = #{value.to_i}").to_s : value
      else out[rename_field(key, type)] = value
      end
    end
    out
  end

  # ── 15. What the assistant remembers of what it did ───────────────────────
  def rewrite_change_sets!
    suppress_messages do
      locked = 0
      select_rows("SELECT id, display, undo_log, operations, undoable FROM assistant_change_sets").each do |id, display, undo_log, operations, undoable|
        display = JSON.parse(display.to_s).filter_map do |row|
          review = row["review"]
          if review.is_a?(Hash) && review["model"]
            mapped = map_model(review["model"], review["id"])
            next row.except("review") unless mapped

            row.merge("review" => review.merge("model" => mapped.first, "id" => mapped.last))
          else
            row
          end
        end

        lock = false
        log = JSON.parse(undo_log.to_s).map do |entry|
          lock ||= %w[updated status uses series completed uncompleted].include?(entry["kind"]) && (OLD_TABLES.key?(entry["model"].to_s) || entry["model"] == "Event")
          if OLD_TABLES.key?(entry["model"].to_s) || %w[MedicalTherapy MedicalTherapyShare].include?(entry["model"])
            mapped = map_model(entry["model"], entry["id"])
            entry = mapped ? entry.merge("model" => mapped.first, "id" => mapped.last) : entry.merge("model" => "Occurrence", "id" => nil)
          end
          if entry["attributes"].is_a?(Hash) && entry["attributes"].key?("medical_therapy_id")
            entry = entry.merge("attributes" => entry["attributes"].except("medical_therapy_id").merge("collection_id" => entry["attributes"]["medical_therapy_id"]))
          end
          entry
        end

        ops = JSON.parse(operations.to_s).map do |op|
          op = op.merge("type" => "collection") if op["type"] == "medical_therapy"
          op["fields"].is_a?(Hash) ? op.merge("fields" => rename_fields(op["fields"], op["type"].to_s.camelize)) : op
        end

        locked += 1 if lock && undoable
        execute "UPDATE assistant_change_sets SET display = #{quote(display.to_json)}, undo_log = #{quote(log.to_json)}, operations = #{quote(ops.to_json)}#{', undoable = FALSE' if lock} WHERE id = #{id}"
      end
      @report[:change_sets_locked] = locked
    end
  end

  # The new model and id of a per-kind row ("Appointment", 12 → "Occurrence",
  # 340), a therapy or a therapy share; nil when the row is gone (a mirror).
  def map_model(model, id)
    case model
    when "MedicalTherapy" then [ "Collection", id ]
    when "MedicalTherapyShare" then [ "CollectionShare", id ]
    else
      table = OLD_TABLES[model.to_s] or return [ model, id ]
      mapped = select_value("SELECT occurrence_id FROM occurrence_map WHERE old_table = #{quote(table)} AND old_id = #{id.to_i}")
      mapped && [ "Occurrence", mapped ]
    end
  end

  # ── 16. The old shape goes ────────────────────────────────────────────────
  def drop_old!
    OLD_TABLES.each_value { |table| drop_table table }
    change_table :events, bulk: true do |t|
      t.remove :eventable_type, :recurrence_rule, :excluded_dates, :times_of_day, :source_event_id
    end
    change_column_null :events, :type, false
    add_index :events, :type
    add_index :events, %i[profile_id type]
    execute "DROP TABLE IF EXISTS mirror_events, orphan_events"
  end

  # ── 17. Nothing lost ──────────────────────────────────────────────────────
  def verify!
    expected_events = @old[:events] - @old[:mirrors] - @report[:orphans_dropped]
    assert_equal expected_events, count("events"), "events"
    assert_equal expected_events, @report[:series_details], "one series details row per event"
    OLD_TABLES.each do |type, table|
      assert_equal 1, select_value("SELECT COALESCE(MAX(c), 1) FROM (SELECT COUNT(*) c FROM #{table.singularize}_details WHERE occurrence_id IS NULL GROUP BY event_id) x").to_i, "#{type}: one series row per event"
    end
    assert_equal @old[:recurring] - count_recurring_lost, count("events WHERE rrule IS NOT NULL"), "recurring series"
    expected_rows = @old[:rows].values.sum - @old[:mirror_rows]
    assert_equal expected_rows, count("occurrences"), "occurrences"
    OLD_TABLES.each do |type, _table|
      lost = type == "Transaction" ? @old[:mirror_rows] : 0
      assert_equal @old[:rows][type] - lost, count("occurrences o JOIN events e ON e.id = o.event_id WHERE e.type = #{quote(type)}"), "#{type} days"
    end
    assert_equal @old[:lab_entries], count("lab_test_result_entries"), "lab entries"
    assert_equal @old[:meal_consumptions], count("meal_consumptions"), "meal consumptions"
    assert_equal @old[:consumptions_drawn], count("supply_consumptions"), "supply consumptions drawn"
    raise "meal_recipes grew" if count("meal_recipes") > @old[:meal_recipes]

    assert_equal @old[:collections], count("collections"), "collections"
    assert_equal @old[:collection_shares], count("collection_shares"), "collection shares"
    assert_equal @old[:purchases_in_collection], count("supply_purchases WHERE collection_id IS NOT NULL"), "purchases in a collection"
    assert_equal @old[:counterparties], count("transaction_details WHERE occurrence_id IS NULL AND counterparty_profile_id IS NOT NULL"), "counterparties"
    assert_equal @old[:day_fees], count("transaction_details WHERE occurrence_id IS NOT NULL AND about_type = 'Occurrence'"), "fees about a day"
    assert_equal count("templates WHERE old_table = 'transactions'") - count("transaction_details WHERE occurrence_id IS NULL AND about_type IS NULL"), count("transaction_details WHERE occurrence_id IS NULL AND about_type IS NOT NULL"), "fees about a series or a purchase"
    assert_equal @old[:approvals_with_record], count("link_approvals WHERE occurrence_id IS NOT NULL") + @report.fetch(:approvals_unmapped, 0), "approvals mapped"
    bad_grants = select_values("SELECT DISTINCT event_type FROM link_grants") - OLD_TABLES.keys
    raise "link grants of an unknown kind: #{bad_grants.inspect}" if bad_grants.any?
    raise "an occurrence without a series" if count("occurrences o LEFT JOIN events e ON e.id = o.event_id WHERE e.id IS NULL").positive?
  end

  def count_recurring_lost
    # Recurring series among the mirrors and orphans are gone with them.
    @old[:recurring] - @rules.size + (@rules.size - @report[:rrules_checked])
  end

  def assert_equal(expected, actual, what)
    raise "cutover check failed: #{what}: expected #{expected}, got #{actual}. Report so far: #{@report.inspect}" unless expected.to_i == actual.to_i
  end

  def count(from) = select_value("SELECT COUNT(*) FROM #{from}").to_i
  def quote(value) = connection.quote(value)
end
