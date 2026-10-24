# frozen_string_literal: true

# A new household, born with its first member's invitation: both or
# neither. That first member is the household's owner. The household's
# errors say what was wrong, the invitation's included (on first_member_email).
#
#   result = Households::Create.call(name: "Rossi", email: "anna@example.com", first_name: "Anna", inviter: current_profile)
#   result.success?     # false (error :invalid): the form shows result.household.errors
#   result.invitation   # Households::Invite::Result, its token for the link; nil when nothing was saved
module Households
  class Create
    Result = ServiceResult.define(:household, :invitation)

    def self.call(name:, email:, inviter:, first_name: nil)
      household = Household.new(name: name, first_member_email: email, first_member_first_name: first_name)
      invitation = nil

      Household.transaction do
        raise ActiveRecord::Rollback unless household.save

        invitation = Invite.call(household, inviter: inviter, email: email, first_name: first_name)
        if invitation.success?
          household.update!(owner: invitation.profile)
          next
        end

        invitation.profile.errors.each { |error| household.errors.add(:first_member_email, error.type, **error.options) }
        invitation = nil
        raise ActiveRecord::Rollback
      end

      # Rolled back: the row is gone, so the form starts from an unsaved household again.
      household = household.dup.tap { |fresh| copy_errors(household, fresh) } if invitation.nil? && household.persisted?
      Result.new(household: household, invitation: invitation, error: (:invalid unless invitation))
    end

    def self.copy_errors(from, to)
      to.first_member_email = from.first_member_email
      to.first_member_first_name = from.first_member_first_name
      from.errors.each { |error| to.errors.add(error.attribute, error.type, **error.options) }
    end
    private_class_method :copy_errors
  end
end
