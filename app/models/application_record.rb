# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  include AccessibleReferences
  include WithinHousehold
  include TypedNames

  primary_abstract_class

  # The rows whose id any of `lookups` names, each a relation selecting one
  # column of ids. Postgres reads each lookup through an index of its own
  # and the rows by their key, where one OR across tables or subqueries
  # would read the whole table, every household's rows with it. A lookup
  # of the same table starts from `unscoped`: called on a narrowed
  # relation, it would otherwise repeat that relation's conditions.
  #
  # The condition is SQL rather than an Arel `IN` on the id: `merge` drops
  # a relation's conditions on a column the other relation also names, so
  # what one person reaches merged with what another reaches would keep
  # only the second person's.
  def self.where_id_in_any(*lookups)
    where("#{quoted_table_name}.#{connection.quote_column_name(primary_key)} IN (#{lookups.map(&:to_sql).join(" UNION ALL ")})")
  end
end
