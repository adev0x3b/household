# frozen_string_literal: true

module Shares
  # Stops sharing: the share row goes, then — once committed — the person
  # hears about it and the kind's on_unshared hook runs. Returns the share.
  #
  #   Shares::Destroy.call(recipe_share, by: alex)
  class Destroy
    def self.call(share, by:)
      thing = share.thing
      share.destroy!

      ActiveRecord.after_all_transactions_commit do
        Notifications::Deliver.call(recipient: share.profile, kind: :unshared, subject: thing, actor: by)
        thing.on_unshared(share, by:)
      end
      share
    end
  end
end
