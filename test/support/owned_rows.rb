# frozen_string_literal: true

# What a household or a person owns, read from the schema rather than
# listed by hand: every row that reaches it through references that can't be
# empty — a profile's household, an event's profile, an occurrence's event —
# or through a polymorphic one that can't (an attachment's record). A
# reference that may be empty points at someone without belonging to them: a
# payment's other side, who last saved a setting.
#
#   rows = OwnedRows.new
#   rows.of(household)   # => { "households" => Set[id], "profiles" => …, "events" => … }
#   rows.of(profile)     # => { "profiles" => Set[id], "events" => … }
#   rows.ownable         # every table a household can own rows in
#   rows.ownable(by: "profiles")   # … or a person
#   rows.pointing        # the references that may be empty
#   rows.dangling        # polymorphic references to rows that are gone
class OwnedRows
  # One table's reference to another: `owner` is nil when polymorphic (the
  # owner's class is in the column's _type twin).
  Reference = Data.define(:table, :column, :owner, :null) do
    def polymorphic? = owner.nil?
    def type_column = column.delete_suffix("_id") + "_type"
  end

  def initialize(connection = ActiveRecord::Base.connection)
    @connection = connection
  end

  def of(owner)
    owned = Hash.new { |hash, table| hash[table] = Set.new }
    owned[owner.class.table_name] << owner.id
    loop { break if owning.sum { claim(_1, owned) }.zero? }
    owned.reject { |_, ids| ids.empty? }
  end

  # A table with a polymorphic reference that can't be empty hangs off
  # whatever it names, so a household's rows may sit in it.
  def ownable(by: "households")
    tables = Set[by] | owning.select(&:polymorphic?).map(&:table)
    loop do
      more = owning.filter_map { |ref| ref.table if tables.include?(ref.owner) } - tables.to_a
      break if more.empty?

      tables.merge(more)
    end
    tables.to_a.sort
  end

  # A row that names another through one of these doesn't belong to it.
  def pointing = references.select(&:null)

  # `outliving` names references ("table.column") allowed to name a row
  # that is gone.
  def dangling(outliving: [])
    references.select(&:polymorphic?).reject { outliving.include?("#{_1.table}.#{_1.column}") }.flat_map do |ref|
      @connection.select_rows("SELECT DISTINCT #{ref.type_column} FROM #{ref.table} WHERE #{ref.type_column} IS NOT NULL").flatten.flat_map do |type|
        owner = table_of(type)
        @connection.select_values(<<~SQL).map { "#{ref.table}##{_1}: #{ref.column} names a #{type} that is gone" }
          SELECT id FROM #{ref.table} WHERE #{ref.type_column} = #{@connection.quote(type)}
            AND #{ref.column} IS NOT NULL AND NOT EXISTS (SELECT 1 FROM #{owner} WHERE #{owner}.id = #{ref.table}.#{ref.column})
        SQL
      end
    end
  end

  private

  # Adds to `owned` the rows of the reference's table that name an owned
  # row; how many were new.
  def claim(ref, owned)
    found = if ref.polymorphic?
      @connection.select_rows("SELECT id, #{ref.type_column}, #{ref.column} FROM #{ref.table}")
        .select { |_, type, id| owned[table_of(type)].include?(id) }.map(&:first)
    elsif owned[ref.owner].any?
      @connection.select_values("SELECT id FROM #{ref.table} WHERE #{ref.column} IN (#{owned[ref.owner].to_a.join(", ")})")
    end
    before = owned[ref.table].size
    owned[ref.table].merge(found.to_a)
    owned[ref.table].size - before
  end

  def table_of(type) = type.constantize.table_name

  # The column that holds the id of the row a key points at. A key of
  # several columns (a day's details, to the day and its series) starts with
  # it, and the others only say the row must agree.
  def id_column(key) = Array(key.column).first

  def owning = references.reject(&:null)

  def references
    @references ||= (@connection.tables - %w[schema_migrations ar_internal_metadata]).flat_map do |table|
      columns = @connection.columns(table).index_by(&:name)
      keys = @connection.foreign_keys(table)
      polymorphic = columns.keys.filter_map { |name| name.delete_suffix("_type") + "_id" if name.end_with?("_type") }
        .select { |column| columns.key?(column) && keys.none? { _1.column == column } }

      keys.map { |key| Reference.new(table:, column: id_column(key), owner: key.to_table, null: columns.fetch(id_column(key)).null) } +
        polymorphic.map { Reference.new(table:, column: _1, owner: nil, null: columns.fetch(_1).null) }
    end
  end
end
