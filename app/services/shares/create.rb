# frozen_string_literal: true

module Shares
  # Shares a thing (Shareable) with one of its owner's housemates: the share
  # row, then — once it is committed, so a caller's transaction (the
  # assistant's apply) can still roll it back unseen — a line under the
  # person's bell and the kind's on_shared hook.
  #
  #   result = Shares::Create.call(recipe, with: sam, by: alex)
  #   result.success?   # false: result.share.errors says why
  class Create
    Result = ServiceResult.define(:share)

    def self.call(thing, with:, by:)
      share = thing.shares.build(profile: with)
      return Result.new(share:, error: :invalid) unless share.save

      ActiveRecord.after_all_transactions_commit do
        Notifications::Deliver.call(recipient: with, kind: :shared, subject: thing, actor: by)
        thing.on_shared(share, by:)
      end
      Result.new(share:, error: nil)
    end
  end
end
