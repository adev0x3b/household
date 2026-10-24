# frozen_string_literal: true

# A record may only point at things its owner can access: their own, or
# shared with them. Ids arrive from forms and from the assistant's output,
# so neither is trusted.
#
#   validates_accessible :collection, by: :profile
#   validates_accessible :ingredient, by: -> { recipe&.profile }
#
# The target's class answers `accessible_by(profile)`. A reference is
# checked when it changes, not after, so revoking a share later doesn't
# make the rows that already point at it invalid.
module AccessibleReferences
  extend ActiveSupport::Concern

  Reference = Data.define(:by, :keys)

  included do
    class_attribute :accessible_references, instance_accessor: false, default: {}
  end

  class_methods do
    def validates_accessible(association, by:)
      reflection = reflect_on_association(association)
      keys = [ reflection.foreign_key, (reflection.foreign_type if reflection.polymorphic?) ].compact
      self.accessible_references = accessible_references.merge(association => Reference.new(by: by, keys: keys))

      validate(if: -> { keys.any? { |key| will_save_change_to_attribute?(key) } }) do
        target = public_send(association)
        owner = access_owner(by)
        next if target.nil? || owner.nil? || target.new_record?

        errors.add(association, :inaccessible) unless access_allowed?(association, target, owner)
      end
    end

    # A parent whose lines are checked together reads their answers first.
    def reads_access_of(lines)
      before_validation { association(lines).klass.read_access(association(lines).target.reject(&:marked_for_destruction?)) }
    end

    # Reads, for many records at once, whether each may point at what it
    # points at: one query per kind of target and owner instead of one per
    # record. Each record's own check then takes its answer.
    def read_access(records)
      accessible_references.each do |association, reference|
        ActiveRecord::Associations::Preloader.new(records: records.reject { _1.association(association).loaded? }, associations: association).call
        asked = records.filter_map do |record|
          target = record.public_send(association)
          owner = record.access_owner(reference.by)
          [ record, target, owner ] if reference.keys.any? { record.will_save_change_to_attribute?(_1) } && target && owner && !target.new_record?
        end
        asked.group_by { |_, target, owner| [ target.class, owner ] }.each do |(klass, owner), group|
          next unless klass.respond_to?(:accessible_by)

          allowed = klass.accessible_by(owner).where(id: group.map { _2.id }).pluck(:id).to_set
          group.each { |record, target, _| record.access_answers[association] = [ target, allowed.include?(target.id) ] }
        end
      end
    end
  end

  # The answers read_access found for this record, each for one target.
  def access_answers = @access_answers ||= {}

  # Whose access the reference is checked against: a method of the record,
  # or a block read on it.
  def access_owner(by) = by.is_a?(Proc) ? instance_exec(&by) : public_send(by)

  private

  # The answer read for this very target, taken once; a target changed
  # since is asked about now.
  def access_allowed?(association, target, owner)
    read_for, allowed = access_answers.delete(association)
    return allowed if read_for.equal?(target)

    target.class.respond_to?(:accessible_by) && target.class.accessible_by(owner).exists?(id: target.id)
  end
end
