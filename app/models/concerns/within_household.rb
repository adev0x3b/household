# frozen_string_literal: true

# A record may only point at people and units of its owner's household: a
# share goes to a housemate, a transfer's other side is a housemate, a
# quantity is in one of the household's units. Ids arrive from forms and
# from the assistant's output, so neither is trusted.
#
#   validates_within_household :profile, of: -> { recipe&.profile }
#   validates_within_household :unit, of: :profile
#
# The target must respond to `household_id` (a Profile, a Unit). Checked
# only when the reference changes, like validates_accessible.
module WithinHousehold
  extend ActiveSupport::Concern

  class_methods do
    def validates_within_household(association, of:)
      key = reflect_on_association(association).foreign_key

      validate(if: -> { will_save_change_to_attribute?(key) }) do
        target = public_send(association)
        owner = of.is_a?(Proc) ? instance_exec(&of) : public_send(of)
        next if target.nil? || owner.nil?

        errors.add(association, :outside_household) unless target.household_id == owner.household_id
      end
    end
  end
end
