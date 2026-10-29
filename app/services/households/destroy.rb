# frozen_string_literal: true

# Deletes a household with everything its members keep (Profiles::Destroy),
# then the units and the household itself.
#
#   Households::Destroy.call(Demo::Seeder.household)
#
# Nothing of another household is touched: a household's records never point
# outside it (WithinHousehold).
module Households
  class Destroy
    def self.call(household)
      ActiveRecord::Base.transaction do
        # Its row first, as a drain claiming its mail takes it before the
        # mail's rows: neither then holds what the other waits for.
        household.lock!
        Profiles::Destroy.call(household.profiles.to_a)
        Conversation.where(household_id: household.id).delete_all
        Unit.where(household_id: household.id).delete_all
        household.delete
      end
    end
  end
end
