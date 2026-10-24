# frozen_string_literal: true

# A catalog row a person typed rather than picked: "Saffron" on a recipe
# line, "mg/dL" next to a lab value. While the record is checked the name
# only reads, so that checking writes nothing: it takes the row by that
# name, or holds a new one in memory. The row is made when the record is
# saved, safely against another save making the same name meanwhile.
class TypedName
  attr_reader :record, :association, :name, :row

  # `within` is the owner's part of the catalog, such as a profile's
  # ingredients or a household's units.
  def initialize(record, association, name, within)
    @record = record
    @association = association
    @name = name
    @within = within
  end

  # Reads many names at once, one query per catalog and scope, and gives
  # each record the row its name names.
  def self.read_all(typed_names)
    typed_names.reject(&:read?).group_by { [ _1.catalog, _1.scope ] }.each do |(catalog, scope), names|
      rows = catalog.where(scope).where("LOWER(name) IN (?)", names.map(&:key)).index_by { _1.name.downcase }
      names.each { _1.read(rows[_1.key]) }
    end
  end

  # Makes the rows many names hold new, one statement per catalog and scope.
  def self.make_all(typed_names)
    typed_names.select(&:held_new?).group_by { [ _1.catalog, _1.scope ] }.each do |(catalog, scope), names|
      rows = catalog.find_or_create_all_by_name(names.map(&:name), **scope)
      names.each { _1.made(rows.fetch(_1.key)) }
    end
  end

  def catalog = record.class.reflect_on_association(association).klass
  def scope = @scope ||= @within.call(record)
  def key = name.downcase

  def read? = !row.nil?

  # Whether the record still points at the row this name read; it may have
  # been given another row since.
  def taken? = read? && record.public_send(association).equal?(row)
  def held_new? = taken? && row.new_record?

  # Takes the row by this name, found now or by a batch; a name not in the
  # catalog yet holds a new row, which a form shows again as typed.
  def read(row = catalog.named(name, **scope))
    @row = row || catalog.new(scope.merge(name: name))
    record.public_send(:"#{association}=", @row)
  end

  # Makes the row, or finds the one another save made meanwhile.
  def make = made(catalog.find_or_create_by_name(name, **scope))

  def made(row)
    @row = row
    record.public_send(:"#{association}=", row)
  end
end
