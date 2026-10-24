# frozen_string_literal: true

# A catalog of names, such as a household's units or a profile's
# ingredients: a name is found whatever its case and spacing, and making
# one that another request made at the same moment finds that row.
module IdempotentlyNamed
  extend ActiveSupport::Concern

  included do
    validates :name, presence: true
  end

  class_methods do
    # The name is unique within `column` (a profile, a household), in any
    # case, as the unique index on lower(name) holds it: a form that repeats
    # one says so instead of failing on the index.
    def names_unique_within(column)
      validates :name, uniqueness: { scope: column, case_sensitive: false }
    end

    # The row by that name, made when there is none. The unique index on
    # lower(name) is the guard against two requests making the same name,
    # and the one that loses reads the winner's row rather than failing.
    # `scope` is the part of the catalog a name is unique in, such as
    # `profile_id:`; none where it is unique across the table.
    def find_or_create_by_name(raw_name, **scope)
      name = raw_name.to_s.strip
      return nil if name.blank?

      named(name, **scope) || create_idempotently(name, scope)
    end

    # The rows by these names, those missing made in one statement:
    # { name.downcase => row }. A row made by name holds only its scope and
    # its name, nothing a validation would check, so it is inserted as it
    # is; the unique index skips a name another save made meanwhile, and
    # that row is read with the rest.
    def find_or_create_all_by_name(raw_names, **scope)
      names = raw_names.map { _1.to_s.strip }.compact_blank.uniq(&:downcase)
      return {} if names.empty?

      insert_all(names.map { |name| scope.merge(name: name) })
      where(scope).where("LOWER(name) IN (?)", names.map(&:downcase)).index_by { _1.name.downcase }
    end

    # The row by that name, case and surrounding spaces ignored, or nil: a
    # lookup that writes nothing, for a record being checked.
    def named(raw_name, **scope)
      name = raw_name.to_s.strip
      return nil if name.blank?

      where(scope).find_by("LOWER(name) = ?", name.downcase)
    end

    private

    # In a savepoint, because the losing insert of a race would otherwise
    # abort the transaction it runs in, and the read after it.
    def create_idempotently(name, scope = {})
      transaction(requires_new: true) { create!(scope.merge(name: name)) }
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      raise if e.is_a?(ActiveRecord::RecordInvalid) && !e.record.errors.of_kind?(:name, :taken)

      where(scope).find_by!("LOWER(name) = ?", name.downcase)
    end
  end
end
