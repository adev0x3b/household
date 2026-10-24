# frozen_string_literal: true

# What a record does with the catalog rows its person typed by name
# (TypedName): it reads them while it is checked and makes them when it is
# saved. A record gives each typed name a writer of its own, naming the
# owner's part of the catalog the name is looked up in:
#
#   def unit_name=(name)
#     type_name(:unit, name) { { household_id: profile.household_id } }
#   end
module TypedNames
  extend ActiveSupport::Concern

  included do
    before_validation :read_typed_names
    # Included in ApplicationRecord, so this runs ahead of every model's own
    # belongs_to: its autosave would write a held row as it is, without the
    # catalog's guard against another save making the same name meanwhile.
    before_save :make_typed_names
  end

  class_methods do
    # A parent whose lines type names reads them together, one query per
    # catalog, and makes the new ones in one statement, so that twenty
    # lines cost what two do.
    def reads_typed_names_of(lines)
      before_validation { TypedName.read_all(typed_names_of(lines)) }
      before_save { TypedName.make_all(typed_names_of(lines)) }
    end
  end

  # The names given, by association.
  def typed_names = @typed_names ||= {}

  private

  # The block gives the owner's part of the catalog and runs when the name
  # is looked up, since the owner may be set after the name is. An emptied
  # field names nothing: the row the record had goes with it.
  def type_name(association, name, &within)
    name = name.to_s.strip.presence
    if name
      typed_names[association] = TypedName.new(self, association, name, within)
    else
      typed_names.delete(association)
      public_send(:"#{association}=", nil)
    end
  end

  # A name read already, whose row the record still points at, is not read
  # again: its parent may have read it with the other lines.
  def read_typed_names
    typed_names.each_value { |typed| typed.read unless typed.taken? }
  end

  # A name whose row was never read, or that the record still holds new,
  # is made now; one given another row since is spent.
  def make_typed_names
    typed_names.each_value { |typed| typed.make if !typed.read? || typed.held_new? }
    typed_names.clear
  end

  def typed_names_of(lines)
    association(lines).target.reject(&:marked_for_destruction?).flat_map { _1.typed_names.values }
  end
end
